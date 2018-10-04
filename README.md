# kineo-endpoint

## SPARQL 1.1 Protocol implementation in Swift/Vapor

### Build

```
% swift build -c release
```

### Load data

Create a database file (`geo.db`) and load an N-Triples or Turtle file:

```
% ./.build/release/kineo-create-db geo.db dbpedia-geo.nt
```

### Start the Endpoint

```
./.build/release/kineo-endpoint geo.db
```

### Query

Querying of the data can be done using SPARQL:

```
% curl --data 'query=PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#> SELECT ?s ?lat WHERE { ?s geo:lat ?lat ; geo:long ?long } ORDER BY ?s LIMIT 25' http://localhost:8080/sparql
```

### SPARQL Endpoint

Finally, a SPARQL endpoint can be run, allowing SPARQL Protocol clients to access the data:

```
% ./.build/release/kineo-endpoint geo.db &
% curl -s -H "Accept: application/sparql-results+json" -H "Content-Type: application/sparql-query" --data 'PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#> SELECT ?s ?lat ?long WHERE { ?s geo:lat ?lat ; geo:long ?long } LIMIT 1' 'http://localhost:8080/sparql' | jq .
{
  "head": {
    "vars": [ "s", "lat", "long" ]
  },
  "results": {
    "bindings": [
      {
        "lat": {
          "datatype": "http://www.w3.org/2001/XMLSchema#float",
          "type": "literal",
          "value": "51.78333333333333"
        },
        "long": {
          "datatype": "http://www.w3.org/2001/XMLSchema#float",
          "type": "literal",
          "value": "4.616666666666667"
        },
        "s": {
          "type": "uri",
          "value": "http://dbpedia.org/resource/'s-Gravendeel"
        }
      }
    ]
  }
}
```
