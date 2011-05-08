#!/usr/bin/env perl
use strict;
use warnings;
use Net::Okuyama;

# Connect to okuyama automatically.
my $client = Net::Okuyama->new('localhost:8888', 'localhost:8889');

# Set record.
$client->set(foo => 'bar');
warn $client->get('foo'); # bar

# Get record.
$client->set('foo', 'baz');
warn $client->get('foo'); # baz

# Set tags.
$client->set(foo => 'bar', ['baz']);
warn $client->get('foo'); # bar
