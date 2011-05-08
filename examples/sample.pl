#!/usr/bin/env perl
use strict;
use warnings;
use Perl6::Say;
use Net::Okuyama;

# Connect to okuyama automatically.
my $client = Net::Okuyama->new(hosts => ['localhost:8888', 'localhost:8889']);

# Set a record.
$client->set(foo => 'bar');
say $client->get('foo'); # bar

$client->set('foo', 'baz');
say $client->get('foo'); # baz

# Set tags.
$client->set(foo => 'bar', ['baz']);
say $client->get('foo'); # bar

$client->set(bar => 'baz', ['baz']);
# Get keys.
my $keys = $client->get_keys_by_tag('baz');
for my $key (@{$keys}) {
    say $client->get($key);
}

# Remove.
$client->remove('foo');
$client->remove('bar');

# Close connection.
$client->close;
