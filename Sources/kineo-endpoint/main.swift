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
import DiomedeQuadStore
//import HDT
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
        
        guard let p = RDFSerializationConfiguration.shared.parserFor(filename: filename) else {
            throw KineoEndpoint.EndpointSetupError.parseError("Failed to determine appropriate parser for file: \(filename)")
        }
        
        var quads = [Quad]()
        count = try p.parser.parseFile(filename, mediaType: p.mediaType, base: graph.value) { (s, p, o) in
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
        print("Loading RDF files into default graph (\(defaultGraph)): \(defaultGraphs)")
        count += try parse(store, files: defaultGraphs, graph: defaultGraph, startTime: startSecond)
        
        for (graph, file) in namedGraphs {
            print("Loading RDF file into named graph \(graph): \(file)")
            count = try parse(store, files: [file], graph: graph, startTime: startSecond)
        }
    }
    return count
}

let pageSize = 8192
//RDFSerializationConfiguration.shared.registerParser(HDTRDFParser.self, withType: "application/hdt", extensions: [".hdt"], mediaTypes: [])
guard CommandLine.arguments.count > 1 else {
    guard let pname = CommandLine.arguments.first else { fatalError("Missing command name") }
    print("""
        Usage:
        
            \(pname) -m             [ARGS] [DATASET-DEFINITION]
            \(pname) -q DATABASE.db [ARGS] [DATASET-DEFINITION]
            \(pname) -s DATABASE.sqlite [ARGS] [DATASET-DEFINITION]

        RDF data may be loaded at startup to construct the dataset using:

        Options:
        
        -l, -language
                Enable language-aware processing. (Memory- and SQLite-based
                quadstores only.)
        
                This will use the Accept-Language request header to return
                only localized data that is in a language acceptable to the
                client.
        
        -m, --memory
                Use (non-persistent) in-memory storage for the endpoint data
        
        -s DATABASE.sqlite
                Use the named SQLite database file as persistent storage for
                the endpoint data.

        -q DATABASE.db
                Use the named database file as persistent storage for
                the endpoint data. This uses the Diomede Quadstore (LMDB)
                storage format.

        Dataset Definition:
        
        -d, --default-graph=FILENAME
                Parse RDF from the named file into the default graph. This
                option may be used repeatedly to parse multiple files into
                the default graph.
        
        -n, --named-graph=FILENAME
                Parse RDF from the named file into a graph named with the
                corresponding file: URL.
        
        -D PATH
                Parse RDF files in subdirectories of the supplied path to construct
                a complete RDF dataset. Files in the $PATH/default directory will be
                merged into the default graph. Files in the $PATH/named directory
                will be loaded into a graph named with their corresponding file: URL.
        
        """)
    exit(1)
}

let config = try QuadStoreConfiguration(arguments: &CommandLine.arguments)
var features = [String]()

switch config.type {
case .memoryDatabase, .sqliteMemoryDatabase:
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

SPARQLContentNegotiator.shared.addSerializer(SPARQLHTMLSerializer<SPARQLResultSolution<Term>>())

switch config.type {
case .diomedeDatabase(let filename):
    let fileManager = FileManager.default
    let initialize = !fileManager.fileExists(atPath: filename)
    guard let store = DiomedeQuadStore(path: filename, create: initialize) else {
        fatalError("Failed to construct DiomedeQuadStore")
    }
    if config.languageAware {
        fatalError()
    } else {
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        try load(store: store, configuration: config)
        let app = try endpointApplication(services: services) { (_) in return store }
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Startup")
        }
        #endif
        try app.run()
    }
case .sqliteFileDatabase(let filename):
    let fileManager = FileManager.default
    let initialize = !fileManager.fileExists(atPath: filename)
    let store = try SQLiteQuadStore(filename: filename, initialize: initialize)
    if config.languageAware {
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        try load(store: store, configuration: config)
        let app = try endpointApplication(services: services) { (req) throws -> SQLiteLanguageQuadStore in
            let header = req.http.headers["Accept-Language"].first ?? "*"
            let acceptLanguages = parseAccept(header)
            let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
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
        try load(store: store, configuration: config)
        let app = try endpointApplication(services: services) { (_) in return store }
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Startup")
        }
        #endif
        try app.run()
    }
case .memoryDatabase:
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
case .sqliteMemoryDatabase:
    let store = try SQLiteQuadStore()
    try load(store: store, configuration: config)
    if config.languageAware {
        #if os(macOS)
        if #available(OSX 10.14, *) {
            os_signpost(.event, log: log, name: "Endpoint", "Constructing application model")
        }
        #endif
        let app = try endpointApplication(services: services) { (req) throws -> SQLiteLanguageQuadStore in
            let header = req.http.headers["Accept-Language"].first ?? "*"
            let acceptLanguages = parseAccept(header)
            let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
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
}
