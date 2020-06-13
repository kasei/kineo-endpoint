//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import Kineo
import KineoEndpoint
import DiomedeQuadStore

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
        
        let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
        var quads = [Quad]()
        count = try p.parser.parseFile(filename, mediaType: p.mediaType, defaultGraph: defaultGraph, base: graph.value) { (s, p, o, g) in
            let q = Quad(subject: s, predicate: p, object: o, graph: g)
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
var verbose = true
let argscount = CommandLine.arguments.count
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

let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

switch config.type {
case .diomedeDatabase(let filename):
    let fileManager = FileManager.default
    let initialize = !fileManager.fileExists(atPath: filename)
    guard let store = DiomedeQuadStore(path: filename, create: initialize) else {
        fatalError()
    }
    count += try load(store: store, configuration: config)
case .sqliteFileDatabase(let filename):
    let fileManager = FileManager.default
    let initialize = !fileManager.fileExists(atPath: filename)
    let store = try SQLiteQuadStore(filename: filename, initialize: initialize)
    count += try load(store: store, configuration: config)
case .memoryDatabase, .sqliteMemoryDatabase:
    warn("Database type must be a disk-based database.")
    exit(1)
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
