import Foundation
import Kineo
import SPARQLSyntax
import Vapor
#if os(macOS)
import os.signpost
#endif

public enum EndpointSetupError: Error {
    case parseError(String)
}

public struct ServiceDescription {
    public var supportedLanguages: [QueryLanguage]
    public var resultFormats: [SPARQLContentNegotiator.ResultFormat]
    public var extensionFunctions: [URL]
    public var features: [String]
    public var graphDescriptions: [Term:GraphDescription]
}

public struct EndpointError : Error {
    var status: HTTPResponseStatus
    var message: String
}

public func parseAccept(_ value: String) -> [(String, Double)] {
    var accept = [(String, Double)]()
    let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    for i in items {
        let pair = i.split(separator: ";")
        if pair.count == 1 {
            accept.append((String(pair[0]), 1.0))
        } else if pair.count == 2 {
            if let d = Double(pair[1].dropFirst(2)) { // drop the q= prefix
                accept.append((String(pair[0]), d))
            } else {
                accept.append((String(pair[0]), 0.99)) // make failed-parse items slightly less preferable than items without a q-value
            }
        }
    }
    return accept.sorted { $0.1 > $1.1 }
}


/**
 Evaluate the supplied Query against the database's QuadStore and return an HTTP response.
 If a graph argument is given, use it as the initial active graph.
 
 - parameter query: The query to evaluate.
 */
func evaluate<Q : QuadStoreProtocol>(_ query: Query, using store: Q, dataset: Dataset, acceptHeader: [String]) throws -> HTTPResponse {
    let verbose = false
    let accept = parseAccept(acceptHeader.first ?? "*/*").map { $0.0 }
    
    let e       = QueryPlanEvaluator(store: store, dataset: dataset)
    
    var resp = HTTPResponse(status: .ok)
    
    do {
        let e = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
        if let mtime = try e.effectiveVersion(matching: query) {
            let date = getDateString(seconds: mtime)
            resp.headers.add(name: "Last-Modified", value: "\(date)")
        } else {
            print("No Last-Modified date could be computed")
        }
    } catch QueryError.evaluationError {}
    
    let results = try e.evaluate(query: query)
    
    let negotiator = SPARQLContentNegotiator.shared
    guard let serializer = negotiator.negotiateSerializer(for: results, accept: accept) else {
        throw EndpointError(status: .notAcceptable, message: "No appropriate serializer available for query results")
    }
    resp.headers.replaceOrAdd(name: "Content-Type", value: serializer.canonicalMediaType)
    let data = try serializer.serialize(results)
    resp.body = HTTPBody(data: data)
    return resp
}

func dataset<Q : QuadStoreProtocol>(from components: URLComponents, for store: Q) throws -> Dataset {
    let queryItems = components.queryItems ?? []
    let defaultGraphs = queryItems.filter { $0.name == "default-graph-uri" }.compactMap { $0.value }.map { Term(iri: $0) }
    let namedGraphs = queryItems.filter { $0.name == "named-graph-uri" }.compactMap { $0.value }.map { Term(iri: $0) }
    let dataset = Dataset(defaultGraphs: defaultGraphs, namedGraphs: namedGraphs)
    if dataset.isEmpty {
        let defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
        return Dataset(defaultGraphs: [defaultGraph])
    } else {
        return dataset
    }
}

struct ProtocolRequest : Codable {
    var query: String
    var defaultGraphs: [String]?
    var namedGraphs: [String]?
    
    var dataset: Dataset? {
        let dg = defaultGraphs ?? []
        let ng = namedGraphs ?? []
        let ds = Dataset(defaultGraphs: dg.map { Term(iri: $0) }, namedGraphs: ng.map { Term(iri: $0) })
        return ds.isEmpty ? nil : ds
    }
}

private func serialize(serviceDescription sd: ServiceDescription, for components: URLComponents) -> HTTPResponse {
    var c = components
    c.fragment = nil
    if let qi = c.queryItems {
        let ignore = Set(["query", "default-graph-uri", "named-graph-uri"])
        c.queryItems = qi.filter { !ignore.contains($0.name.lowercased()) }
    } else {
        c.query = nil
    }
    let url = c.url!
    
    var output = """
    @prefix sd: <http://www.w3.org/ns/sparql-service-description#> .
    @prefix void: <http://rdfs.org/ns/void#> .
    
    [] a sd:Service ;
    sd:endpoint <\(url.absoluteString)> ;
    
    """
    
    if sd.supportedLanguages.count > 0 {
        output += "    sd:supportedLanguage \(sd.supportedLanguages.map {"\(Term(iri: $0.rawValue))"}.joined(separator: ", ")) ;\n"
    }
    
    if sd.resultFormats.count > 0 {
        output += "    sd:resultFormat \(sd.resultFormats.map {"\(Term(iri: $0.rawValue))"}.joined(separator: ", ")) ;\n"
    }
    
    if sd.extensionFunctions.count > 0 {
        output += "    sd:extensionFunction \(sd.extensionFunctions.map {"\(Term(iri: $0.absoluteString))"}.joined(separator: ", ")) ;\n"
    }
    
    if sd.features.count > 0 {
        output += "    sd:feature \(sd.features.map {"\(Term(iri: $0))"}.joined(separator: ", ")) ;\n"
    }
    
    // TODO: serialize sd.graphDescriptions
    
    output += "\t.\n"
    
    var resp = HTTPResponse(status: .ok, body: output)
    resp.headers.add(name: "Content-Type", value: "text/turtle")
    return resp
}

private func get<Q: QuadStoreProtocol>(req : Request, store: Q) throws -> HTTPResponse {
    do {
        let u = req.http.url
        guard let components = URLComponents(string: u.absoluteString) else { throw EndpointError(status: .badRequest, message: "Failed to access URL components") }
        let queryItems = components.queryItems ?? []
        let queries = queryItems.filter { $0.name == "query" }.compactMap { $0.value }
        if let sparql = queries.first {
            // Run a query
            guard let sparqlData = sparql.data(using: .utf8) else { throw EndpointError(status: .badRequest, message: "Failed to interpret SPARQL as utf-8") }
            guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
            let query = try p.parseQuery()
            
            let accept = req.http.headers["Accept"]
            
            let ds = try dataset(from: components, for: store)
            return try evaluate(query, using: store, dataset: ds, acceptHeader: accept)
        } else {
            // Return a Service Description
            do {
                let ds = try dataset(from: components, for: store)
                let e = SimpleQueryEvaluator(store: store, dataset: ds, verbose: false)
                let features : [String] = e.supportedFeatures.map { $0.rawValue }
                let negotiator = SPARQLContentNegotiator.shared
                let sd = ServiceDescription(
                    supportedLanguages: e.supportedLanguages,
                    resultFormats: negotiator.supportedSerializations,
                    extensionFunctions: [],
                    features: features,
                    graphDescriptions: [:] // TODO: add graph descriptions
                )
                
                return serialize(serviceDescription: sd, for: components)
            } catch let e {
                let output = "*** Failed to generate service description: \(e)"
                return HTTPResponse(status: .internalServerError, body: output)
            }
        }
    } catch let e {
        if let err = e as? EndpointError {
            return HTTPResponse(status: err.status, body: err.message)
        }
        let output = "*** Failed to evaluate query:\n*** - \(e)"
        return HTTPResponse(status: .internalServerError, body: output)
    }
}

func logQuery<T>(_ object: AnyObject, _ handler: () throws -> T) rethrows -> T {
    #if os(macOS)
    if #available(OSX 10.14, *) {
        let startTime = getCurrentTime()
        let log = OSLog(subsystem: "us.kasei.kineo.endpoint", category: .pointsOfInterest)
        let signpostID = OSSignpostID(log: log, object: object)
        do {
            os_signpost(.begin, log: log, name: "Query Evaluation", signpostID: signpostID, "Begin")
            let r = try handler()
            let endTime = getCurrentTime()
            let elapsed = endTime - startTime
            os_signpost(.end, log: log, name: "Query Evaluation", signpostID: signpostID, "Finished in %{public}lfs", elapsed)
            return r
        } catch let error {
            let endTime = getCurrentTime()
            let elapsed = endTime - startTime
            os_signpost(.end, log: log, name: "Query Evaluation", signpostID: signpostID, "Failed in %{public}lfs: %@", elapsed, String(describing: error))
            throw error
        }
    } else {
        return try handler()
    }
    #else
    return try handler()
    #endif
}

public func endpointApplication<Q: QuadStoreProtocol>(services: Services? = nil, constructQuadStore: @escaping (Request) throws -> Q) throws -> Application {
    let services = services ?? Services.default()
    let app = try Application(services: services)
    let router = try app.make(Router.self)
    router.get("sparql") { (req) -> HTTPResponse in
        return try logQuery(req) {
            let store = try constructQuadStore(req)
            return try get(req: req, store: store)
        }
    }
    
    router.post("sparql") { (req) -> HTTPResponse in
        do {
            return try logQuery(req) {
                let u = req.http.url
                guard let components = URLComponents(string: u.absoluteString) else { throw EndpointError(status: .badRequest, message: "Failed to access URL components") }
                
                let ct = req.http.headers["Content-Type"].first
                let accept = req.http.headers["Accept"]
                
                let store = try constructQuadStore(req)
                switch ct {
                case .none, .some("application/sparql-query"):
                    guard let sparqlData = req.http.body.data else { throw EndpointError(status: .badRequest, message: "No query supplied") }
                    guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
                    let query = try p.parseQuery()
                    let ds = try dataset(from: components, for: store)
                    return try evaluate(query, using: store, dataset: ds, acceptHeader: accept)
                case .some("application/x-www-form-urlencoded"):
                    guard let formData = req.http.body.data else { throw EndpointError(status: .badRequest, message: "No form data supplied") }
                    let q = try URLEncodedFormDecoder().decode(ProtocolRequest.self, from: formData)
                    guard let sparqlData = q.query.data(using: .utf8) else { throw EndpointError(status: .badRequest, message: "No query supplied") }
                    guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
                    let query = try p.parseQuery()
                    let ds = try q.dataset ?? dataset(from: components, for: store) // TOOD: access dataset IRIs from POST body
                    return try evaluate(query, using: store, dataset: ds, acceptHeader: accept)
                case .some(let c):
                    throw EndpointError(status: .badRequest, message: "Unrecognized Content-Type: \(c)")
                }
            }
        } catch let e {
            if let err = e as? EndpointError {
                return HTTPResponse(status: err.status, body: err.message)
            }
            let output = "*** Failed to evaluate query:\n*** - \(e)"
            return HTTPResponse(status: .internalServerError, body: output)
        }
    }
    return app
}
