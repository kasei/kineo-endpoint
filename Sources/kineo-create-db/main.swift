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

/**
 If necessary, create a new quadstore in the supplied database.
 */
func setup<D : PageDatabase>(_ database: D, version: Version) throws {
    try database.update(version: version) { (m) in
        Logger.shared.push(name: "QuadStore setup")
        defer { Logger.shared.pop(printSummary: false) }
        do {
            _ = try MediatedPageQuadStore.create(mediator: m)
        } catch let e {
            warn("*** \(e)")
            throw DatabaseUpdateError.rollback
        }
    }
}


/**
 Parse the supplied RDF files and load the resulting RDF triples into the database's
 QuadStore in the supplied named graph (or into a graph named with the corresponding
 filename, if no graph name is given).
 
 - parameter files: Filenames of Turtle or N-Triples files to parse.
 - parameter startTime: The timestamp to use as the database transaction version number.
 - parameter graph: The graph into which parsed triples should be load.
 */
func parse<D : PageDatabase>(_ database: D, files: [String], startTime: UInt64, graph defaultGraphTerm: Term? = nil) throws -> Int {
    var count   = 0
    let version = Version(startTime)
    try database.update(version: version) { (m) in
        do {
            for filename in files {
                #if os (OSX)
                    guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
                #else
                    let path = NSURL(fileURLWithPath: filename).absoluteString
                #endif
                let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)

                let parser = RDFParser()
                var quads = [Quad]()
                print("Parsing RDF...")
                count = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
                    let q = Quad(subject: s, predicate: p, object: o, graph: graph)
                    quads.append(q)
                }

                print("Loading RDF...")
                let store = try MediatedPageQuadStore.create(mediator: m)
                try store.load(quads: quads)
            }
        } catch let e {
            warn("*** Failed during load of RDF (\(count) triples handled); \(e)")
            throw DatabaseUpdateError.rollback
        }
    }
    return count
}

/**
 Print basic information about the database's QuadStore including the last-modified time,
 the number of quads, the available indexes, and the count of triples in each graph.
 */
func printSummary<D : PageDatabase>(of database: D) throws {
    database.read { (m) in
        guard let store = try? MediatedPageQuadStore(mediator: m) else { return }
        print("Quad Store")
        if let v = try? store.effectiveVersion(), let version = v {
            let versionDate = getDateString(seconds: version)
            print("Version: \(versionDate)")
        }
        print("Quads: \(store.count)")

        let indexes = store.availableQuadIndexes.joined(separator: ", ")
        print("Indexes: \(indexes)")
        
        for graph in store.graphs() {
            let pattern = QuadPattern(
                subject: .variable("s", binding: true),
                predicate: .variable("p", binding: true),
                object: .variable("o", binding: true),
                graph: .bound(graph)
            )
            let count = store.count(matching: pattern)
            print("Graph: \(graph) (\(count) triples)")
        }
        
        print("")
    }
    
}

var verbose = true
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
var pageSize = 8192
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] database.db [-g GRAPH-IRI] rdf.nt ...")
    print("")
    exit(1)
}

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

guard let filename = args.next() else { fatalError("Missing filename") }
guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open \(filename)"); exit(1) }
let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

try setup(database, version: Version(startSecond))
do {
    var graph: Term? = nil
    if let next = args.peek(), next == "-g" {
        _ = args.next()
        guard let iri = args.next() else { fatalError("No IRI value given after -g") }
        graph = Term(value: iri, type: .iri)
    }
    
    count = try parse(database, files: args.elements(), startTime: startSecond, graph: graph)
} catch let e {
    warn("*** Failed to load data: \(e)")
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
//    Logger.shared.printSummary()
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
