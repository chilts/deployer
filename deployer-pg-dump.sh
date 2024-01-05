#!/bin/bash

DIR="$1"
if [ -z "$DIR" ]; then
    echo "$0: Provide a DIR"
    exit 2
fi

DATABASE_URL="$2"
if [ -z "$DATABASE_URL" ]; then
    echo "$0: Provide a DATABASE_URL"
    exit 2
fi

DATE=$(date +\%Y\%m\%d-\%H\%M\%S)

pg_dump --file="$DIR/$DATE.sql" $DATABASE_URL
