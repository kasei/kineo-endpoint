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

let pageSize = 8192
guard CommandLine.arguments.count > 1 else { warn("No database filename given."); exit(1) }
var filename : String = ""
var language : Bool = false

while true {
    filename = CommandLine.arguments.removeLast()
    if filename == "-l" {
        language = true
        guard CommandLine.arguments.count > 1 else { warn("No database filename given."); exit(1) }
        continue
    }
    break
}

guard filename != "" else {
    warn("No database filename found in CommandLine.arguments: \(CommandLine.arguments)")
    exit(1)
}
guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open database file '\(filename)'"); exit(1) }

let app = try endpointApplication(for: database, bindTo: ("0.0.0.0", 8080), languageConneg: language)
try app.run()
