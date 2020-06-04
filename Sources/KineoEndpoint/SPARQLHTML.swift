//
//  SPARQLHTML.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/24/18.
//

import Foundation
import SPARQLSyntax
import Kineo
import HTMLString

public struct SPARQLHTMLSerializer<T: ResultProtocol> : SPARQLSerializable where T.TermType == Term {
    public var serializesTriples = true
    public var serializesBindings = true
    public var serializesBoolean = true
    
    typealias ResultType = T
    public let canonicalMediaType = "text/html"
    public var acceptableMediaTypes = ["text/html"]
    public var htmlTemplate: String
    
    public init() {
        htmlTemplate = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8" />
            <title>Query Results</title>
            <style type="text/css">
                table { border: 1px solid #000; padding: 0; border-collapse: collapse; }
                td, th { border: 1px solid #000; margin: 0; padding: 0 5px; }
            </style>
        </head>
        <body>
        <h1>Query Results</h1>
        {QueryResults}
        </body>
        </html>
        """
    }

    public func serialize<R: Sequence, T: Sequence>(_ results: QueryResult<R, T>) throws -> Data where R.Element == SPARQLResultSolution<Term>, T.Element == Triple {
        let d = try _serialize(results)
        let template = "{QueryResults}".data(using: .utf8)!
        var dd = htmlTemplate.data(using: .utf8)!
        let range = dd.range(of: template)!
        dd.replaceSubrange(range, with: d)
        return dd
    }
    
    public func _serialize<R: Sequence, T: Sequence>(_ results: QueryResult<R, T>) throws -> Data where R.Element == SPARQLResultSolution<Term>, T.Element == Triple {
        switch results {
        case .boolean(let v):
            let s = v ? "true" : "false"
            return s.data(using: .utf8)!
        case let .bindings(vars, seq):
            let colHeads = vars.map { "<th>?\($0)</th>" }.joined()
            var d = "<table>\n".data(using: .utf8)!
            
            let thead = """
                <thead>
                    <tr>\(colHeads)</tr>
                </thead>
            
            """
            
            d += thead.data(using: .utf8)!
            d += "\t<tbody>\n".data(using: .utf8)!
            for result in seq {
                d += "\t\t<tr>".data(using: .utf8)!
                let terms = vars.map { result[$0] }
                let strings = try terms.map { (t) -> String in
                    if let t = t {
                        guard let termString = t.htmlStringEscaped else {
                            throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
                        }
                        return "<td>\(termString)</td>"
                    } else {
                        return "<td></td>"
                    }
                }
                
                let line = strings.joined(separator: "")
                guard let lineData = line.data(using: .utf8) else {
                    throw SerializationError.encodingError("Failed to encode result row as utf-8")
                }
                d.append(lineData)
                d += "</tr>\n".data(using: .utf8)!
            }
            d += "\t</tbody>\n".data(using: .utf8)!
            d += "</table>\n".data(using: .utf8)!

            return d
        case .triples(let triples):
            let colHeads = ["subject", "predicate", "object"].map { "<th>?\($0)</th>" }
            var d = "<table>\n".data(using: .utf8)!
            
            let thead = """
            <thead>
            <tr>\(colHeads)</tr>
            </thead>
            """
            
            d += thead.data(using: .utf8)!
            d += "<tbody>\n".data(using: .utf8)!
            for triple in triples {
                d += "<tr>".data(using: .utf8)!
                let terms = [triple.subject, triple.predicate, triple.object]
                let strings = try terms.map { (t) -> String in
                    guard let termString = t.htmlStringEscaped else {
                        throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
                    }
                    return "<td>\(termString)</td>"
                }
                
                let line = strings.joined(separator: "")
                guard let lineData = line.data(using: .utf8) else {
                    throw SerializationError.encodingError("Failed to encode triple row as utf-8")
                }
                d.append(lineData)
                d += "</tr>\n".data(using: .utf8)!
            }
            d += "</tbody>\n".data(using: .utf8)!
            d += "</table>\n".data(using: .utf8)!
            
            return d
        }
    }
}

private extension String {
    var htmlStringEscaped: String {
        var escaped = ""
        for c in self {
            switch c {
            case Character(UnicodeScalar(0x22)):
                escaped += "\\\""
            case Character(UnicodeScalar(0x5c)):
                escaped += "\\\\"
            case Character(UnicodeScalar(0x09)):
                escaped += "\\t"
            case Character(UnicodeScalar(0x0a)):
                escaped += "\\n"
            default:
                escaped.append(c)
            }
        }
        return escaped
    }
}

private extension Term {
    var htmlStringEscaped: String? {
        switch self.type {
        case .iri:
            return "<a href=\"\(value.addingUnicodeEntities)\">\(value.addingUnicodeEntities)</a>"
        case .blank:
            return "_:\(self.value)"
        case .language(let l):
            return "\"\(value.htmlStringEscaped)\"@\(l)"
        case .datatype(.integer):
            return "\(Int(self.numericValue))"
        case .datatype(.string):
            return "\"\(value.htmlStringEscaped)\""
        case .datatype(let dt):
            return "\"\(value.htmlStringEscaped)\"^^&lt;\(dt.value)&gt;"
        }
    }
}
