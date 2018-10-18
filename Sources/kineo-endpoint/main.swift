//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import KineoEndpoint
import SPARQLSyntax
import Kineo
import Vapor
#if os(macOS)
import os.signpost
#endif

/**
 Parse the supplied RDF files and load the resulting RDF triples into the database's
 QuadStore in the supplied named graph (or into a graph named with the corresponding
 filename, if no graph name is given).
 
 - parameter files: Filenames of Turtle or N-Triples files to parse.
 - parameter startTime: The timestamp to use as the database transaction version number.
 - parameter graph: The graph into which parsed triples should be load.
 */
func parse<Q : MutableQuadStoreProtocol>(_ store: Q, files: [String], graph defaultGraphTerm: Term? = nil, startTime: UInt64 = 0) throws -> Int {
    var count   = 0
    let version = Version(startTime)
    for filename in files {
        #if os (OSX)
        guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
        #else
        let path = NSURL(fileURLWithPath: filename).absoluteString
        #endif
        let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
        
        let parser = RDFParser()
        var quads = [Quad]()
        count = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
            let q = Quad(subject: s, predicate: p, object: o, graph: graph)
            quads.append(q)
        }
        
        try store.load(version: version, quads: quads)
        print("Store count: \(store.count)")
    }
    return count
}

@discardableResult
func load<Q: MutableQuadStoreProtocol>(store: Q, configuration config: QuadStoreConfiguration) throws -> Int {
    var count = 0
    let startSecond = getCurrentDateSeconds()
    if case let .loadFiles(defaultGraphs, namedGraphs) = config.initialize {
        let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
        print("Loading RDF files into default graph: \(defaultGraphs)")
        count += try parse(store, files: defaultGraphs, graph: defaultGraph, startTime: startSecond)
        
        for (graph, file) in namedGraphs {
            print("Loading RDF file into named graph: \(file)")
            count = try parse(store, files: [file], graph: graph, startTime: startSecond)
        }
    }
    return count
}

let pageSize = 8192
guard CommandLine.arguments.count > 1 else {
    warn("No database filename given.")
    exit(1)
}

print("Command-line arguments: \(CommandLine.arguments)")
let config = try QuadStoreConfiguration(arguments: &CommandLine.arguments)

var features = [String]()

switch config.type {
case .memoryDatabase:
    features.append("in-memory")
default:
    features.append("disk-based")
}

if config.languageAware {
    features.append("language-aware")
}

print("Constructing \(features.joined(separator: ", ")) quadstore")

var services = Services.default()
let hostname = "0.0.0.0"
let port = 8080
services.register(NIOServerConfig.default(hostname: hostname, port: port))

#if os(macOS)
var log: OSLog!
if #available(OSX 10.14, *) {
    log = OSLog(subsystem: "us.kasei.kineo.endpoint", category: .pointsOfInterest)
} else if #available(OSX 10.12, *) {
    log = .disabled
}
#endif

if case .memoryDatabase = config.type {
    let store = MemoryQuadStore()
    try load(store: store, configuration: config)
    if config.languageAware {
        #if os(macOS)
        if #available(OSX 10.14, *) {
        os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        let app = try endpointApplication(services: services) { (req) throws -> LanguageMemoryQuadStore in
            let header = req.http.headers["Accept-Language"].first ?? "*"
            let acceptLanguages = parseAccept(header)
            let lstore = LanguageMemoryQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
            return lstore
        }
        #if os(macOS)
        if #available(OSX 10.14, *) {
        os_signpost(.event, log: log, name: "Endpoint", "Startup")
        }
        #endif
        try app.run()
    } else {
        #if os(macOS)
        if #available(OSX 10.14, *) {
        os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        let app = try endpointApplication(services: services) { (_) in return store }
        #if os(macOS)
        if #available(OSX 10.14, *) {
        os_signpost(.event, log: log, name: "Endpoint", "Startup")
        }
        #endif
        try app.run()
    }
} else {
    guard case .filePageDatabase(let filename) = config.type else {
        warn("No database filename available")
        exit(1)
    }
    
    guard let database = FilePageDatabase(filename, size: pageSize) else {
        warn("Failed to open database file '\(filename)'")
        exit(1)
    }
    if config.languageAware {
        #if os(macOS)
        if #available(OSX 10.14, *) {
        os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        let app = try endpointApplication(services: services) { (req) throws -> LanguagePageQuadStore<FilePageDatabase> in
            let header = req.http.headers["Accept-Language"].first ?? "*"
            let acceptLanguages = parseAccept(header)
            let store = try LanguagePageQuadStore(database: database, acceptLanguages: acceptLanguages)
            try load(store: store, configuration: config)
            return store
        }
        #if os(macOS)
        if #available(OSX 10.14, *) {
        os_signpost(.event, log: log, name: "Endpoint", "Startup")
        }
        #endif
        try app.run()
    } else {
        let store = try PageQuadStore(database: database)
        try load(store: store, configuration: config)
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        let app = try endpointApplication(services: services) { (_) in return store }
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Startup")
        }
        #endif
        try app.run()
    }
}
