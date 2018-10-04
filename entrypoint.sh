#!/bin/bash

set -e

DATADIR="/endpoint"
DBFILE="$DATADIR/endpoint.db"

if [ ! -f "$DBFILE" ]; then
	echo "Creating endpoint database file $DBFILE..."
	for f in /data/*; do
		if [ -f $f ]; then
			echo "Loading RDF from ${f}..."
			kineo-create-db "$DBFILE" "$f"
		fi
	done
fi

set -- "$@" $DBFILE
exec "$@"
