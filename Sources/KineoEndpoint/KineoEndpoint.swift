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
    public var dataset: DatasetProtocol
    public var graphDescriptions: [Term:GraphDescription]
    public var prefixes: [String:Term]
    
    public init(supportedLanguages: [QueryLanguage], resultFormats: [SPARQLContentNegotiator.ResultFormat], extensionFunctions: [URL], features: [String], dataset: DatasetProtocol, graphDescriptions: [Term:GraphDescription], prefixes: [String:Term]) {
        self.supportedLanguages = supportedLanguages
        self.resultFormats = resultFormats
        self.extensionFunctions = extensionFunctions
        self.features = features
        self.dataset = dataset
        self.graphDescriptions = graphDescriptions
        self.prefixes = prefixes
    }

    public init<Q: QuadStoreProtocol>(from store: Q, withDataset ds: DatasetProtocol, graphDescriptionLimit: Int = 100) throws {
        let e = SimpleQueryEvaluator(store: store, dataset: ds, verbose: false)
        let features : [String] = e.supportedFeatures.map { $0.rawValue }
        let negotiator = SPARQLContentNegotiator.shared
        let descriptions : [Term:GraphDescription]
        if store.graphsCount > graphDescriptionLimit {
            descriptions = [:]
        } else {
            descriptions = store.graphDescriptions
        }

        self.init(
            supportedLanguages: e.supportedLanguages,
            resultFormats: negotiator.supportedSerializations,
            extensionFunctions: [],
            features: features,
            dataset: ds,
            graphDescriptions: descriptions,
            prefixes: [:]
        )
        
        if let d = store as? PrefixNameStoringQuadStore {
            self.prefixes = d.prefixes
        }
    }

    public func serialize(for components: URLComponents) -> HTTPResponse {
        let sd = self
        var c = components
        c.fragment = nil
        if let qi = c.queryItems {
            let ignore = Set(["query", "default-graph-uri", "named-graph-uri"])
            c.queryItems = qi.filter { !ignore.contains($0.name.lowercased()) }
        } else {
            c.query = nil
        }
        let url = c.url!
        
        let endpoint = Term(iri: url.absoluteString).ntriplesString()
        var output = """
        @prefix sd: <http://www.w3.org/ns/sparql-service-description#> .
        @prefix void: <http://rdfs.org/ns/void#> .
        @prefix vann: <http://purl.org/vocab/vann/> .
        
        [] a sd:Service ;
            sd:endpoint \(endpoint) ;
        
        """
        
        if sd.supportedLanguages.count > 0 {
            output += "    sd:supportedLanguage \(sd.supportedLanguages.map {"\(Term(iri: $0.rawValue).ntriplesString())"}.joined(separator: ", ")) ;\n"
        }
        
        if sd.resultFormats.count > 0 {
            output += "    sd:resultFormat \(sd.resultFormats.map {"\(Term(iri: $0.rawValue).ntriplesString())"}.joined(separator: ", ")) ;\n"
        }
        
        if sd.extensionFunctions.count > 0 {
            output += "    sd:extensionFunction \(sd.extensionFunctions.map {"\(Term(iri: $0.absoluteString).ntriplesString())"}.joined(separator: ", ")) ;\n"
        }
        
        if sd.features.count > 0 {
            output += "    sd:feature \(sd.features.map {"\(Term(iri: $0).ntriplesString())"}.joined(separator: ", ")) ;\n"
        }
        
        output += "    sd:defaultDataset [\n"
        output += "        a sd:Dataset ;\n"
        if let defaultGraph = sd.dataset.defaultGraphs.first, let graphDescription = sd.graphDescriptions[defaultGraph] {
            output += "        sd:defaultGraph [\n"
            output += "            a sd:Graph ;\n"
            output += "            void:triples \(graphDescription.triplesCount) ;\n"
            output += "        ] ;\n"
        }
        
        for namedGraph in sd.graphDescriptions.keys {
            if let graphDescription = sd.graphDescriptions[namedGraph] {
                let ng = namedGraph.ntriplesString()
                output += "        sd:namedGraph [\n"
                output += "            a sd:NamedGraph ;\n"
                output += "            sd:name \(ng) ;\n"
                output += "            sd:graph [\n"
                output += "                a sd:Graph ;\n"
                output += "                void:triples \(graphDescription.triplesCount) ;\n"
                output += "            ] ;\n"
                output += "        ] ;\n"
            }
        }
        output += "    ] ;\n"
        
        if !self.prefixes.isEmpty {
            output += "    sd:namespaces\n"
            var decls = [String]()
            let pairs = self.prefixes.sorted { $0.key.lexicographicallyPrecedes($1.key) }
            for (_name, _iri) in pairs {
                let name = Term(string: _name).ntriplesString()
                let iri = Term(string: _iri.value).ntriplesString()
                var prefixDefn = ""
                prefixDefn += "        [\n"
                prefixDefn += "            vann:preferredNamespacePrefix \(name) ;\n"
                prefixDefn += "            vann:preferredNamespaceUri \(iri) ;\n"
                prefixDefn += "        ]"
                decls.append(prefixDefn)
            }
            output += decls.joined(separator: " ,\n")
            output += "    ;\n"
        }
        
        output += "\t.\n"
        
        var resp = HTTPResponse(status: .ok, body: output)
        resp.headers.add(name: "Content-Type", value: "text/turtle")
        return resp
    }
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
func evaluate<Q : QuadStoreProtocol>(_ query: Query, using store: Q, dataset: DatasetProtocol, acceptHeader: [String]) throws -> HTTPResponse {
    let verbose = false
    let accept = parseAccept(acceptHeader.first ?? "*/*").map { $0.0 }
    
//    print(query.serialize())
//    let e = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)

    let USE_SIMPLE = false
    var resp = HTTPResponse(status: .ok)
    
    do {
        let e = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
        if let mtime = try e.effectiveVersion(matching: query) {
            let date = getDateString(seconds: mtime)
            resp.headers.add(name: "Last-Modified", value: "\(date)")
        } else {
            print("No Last-Modified date could be computed")
        }
        
        if USE_SIMPLE {
            let results = try e.evaluate(query: query)
            return try response(for: results, accept: accept)
        }
    } catch QueryError.evaluationError {}


    let e       = QueryPlanEvaluator(store: store, dataset: dataset, verbose: true)
    let results = try e.evaluate(query: query)
    return try response(for: results, accept: accept)
}

func response<S: Sequence>(for results: QueryResult<S, [Triple]>, accept: [String]) throws -> HTTPResponse where S.Element == SPARQLResultSolution<Term> {
    var resp = HTTPResponse(status: .ok)
    let negotiator = SPARQLContentNegotiator.shared
    guard let serializer = negotiator.negotiateSerializer(for: results, accept: accept) else {
        throw EndpointError(status: .notAcceptable, message: "No appropriate serializer available for query results")
    }
    resp.headers.replaceOrAdd(name: "Content-Type", value: serializer.canonicalMediaType)
    let data = try serializer.serialize(results)
    resp.body = HTTPBody(data: data)
    return resp
}

func dataset<Q : QuadStoreProtocol>(from components: URLComponents, for store: Q, defaultGraph: Term? = nil) throws -> DatasetProtocol {
    let queryItems = components.queryItems ?? []
    let defaultGraphs = queryItems.filter { $0.name == "default-graph-uri" }.compactMap { $0.value }.map { Term(iri: $0) }
    let namedGraphs = queryItems.filter { $0.name == "named-graph-uri" }.compactMap { $0.value }.map { Term(iri: $0) }
    let dataset = Dataset(defaultGraphs: defaultGraphs, namedGraphs: namedGraphs)
    if dataset.isEmpty {
        return store.dataset()
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

private func get<Q: QuadStoreProtocol>(req : Request, store: Q, defaultGraph: Term?) throws -> HTTPResponse {
    do {
        let u = req.http.url
        guard let components = URLComponents(string: u.absoluteString.replacingOccurrences(of: "+", with: "%20")) else { throw EndpointError(status: .badRequest, message: "Failed to access URL components") }
        let queryItems = components.queryItems ?? []
        let queries = queryItems.filter { $0.name == "query" }.compactMap { $0.value }
        if let sparql = queries.first {
            // Run a query
            guard let sparqlData = sparql.data(using: .utf8) else { throw EndpointError(status: .badRequest, message: "Failed to interpret SPARQL as utf-8") }
            guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
            let query = try p.parseQuery()
            
            let accept = req.http.headers["Accept"]
            
            let ds = try dataset(from: components, for: store, defaultGraph: defaultGraph)
            return try evaluate(query, using: store, dataset: ds, acceptHeader: accept)
        } else {
            // Return a Service Description
            do {
                let ds = try dataset(from: components, for: store)
                let sd = try ServiceDescription(from: store, withDataset: ds)
                return sd.serialize(for: components)
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

public func endpointApplication<Q: QuadStoreProtocol>(services: Services? = nil, defaultGraph: Term? = nil, constructQuadStore: @escaping (Request) throws -> Q) throws -> Application {
    let services = services ?? Services.default()
    let app = try Application(services: services)
    let router = try app.make(Router.self)
    
    router.get("") { (req) -> HTTPResponse in
        return HTTPResponse(status: .ok, headers: ["Content-Type": "text/html"], body: """
            <form action="/sparql" method="get">
                <div class="textarea">
                    <label for="query">Query:</label><br/>
                    <textarea id="query" cols="100" name="query" rows="30"></textarea>
                </div>
                <div>
                    <button id="submit" type="submit">Submit</button>
                </div>
            </form>
        """)
    }
    
    router.get("sparql") { (req) -> HTTPResponse in
        return try logQuery(req) {
            let store = try constructQuadStore(req)
            return try get(req: req, store: store, defaultGraph: defaultGraph)
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
                    let ds = try dataset(from: components, for: store, defaultGraph: defaultGraph)
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
