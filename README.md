# kineo-endpoint

## SPARQL 1.1 Protocol implementation in Swift/Vapor

### Build

```
% swift build -c release
```

### Creating an in-memory endpoint

Create an in-memory endpoint with data loaded into the default graph:

```
% ./.build/release/kineo-endpoint -m --default-graph=examples/geo-data/geo.ttl &
```

### Creating a persistent database endpoint

Alternatively, a persistent database file (`geo.db`) can be created and loaded
with N-Triples or Turtle files offline:

```
% ./.build/release/kineo-create-db -q geo.db --default-graph=examples/geo-data/geo.ttl
```

After loading data, an endpoint can be started using this persistent database:

```
./.build/release/kineo-endpoint -q geo.db &
```

### Query

Querying of the data can be done using SPARQL protocol:

```
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
