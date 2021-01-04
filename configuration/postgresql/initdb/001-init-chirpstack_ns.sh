#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    create role chirpstack_ns with login password 'chirpstack_ns';
    create database eu868 with owner chirpstack_ns;
    create database us915 with owner chirpstack_ns;
    create database au915 with owner chirpstack_ns;
EOSQL

