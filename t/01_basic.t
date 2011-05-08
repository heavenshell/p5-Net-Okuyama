use strict;
use warnings;
use Test::More;
use Test::Exception;
use Data::Dumper;

use Net::Okuyama;
subtest 'Connect to server' => sub {
    my $client = Net::Okuyama->new(hosts => 'localhost:8888');
    is(ref $client, 'Net::Okuyama');
    is($client->{host}, 'localhost:8888');

    $client = Net::Okuyama->new(hosts => ['localhost:8888', 'localhost:8889']);
    is_deeply($client->{host}, ('localhost:8888', 'localhost:8889'));

    $client = Net::Okuyama->new;
    is($client->{host}, 'localhost:8888');

    eval {Net::Okuyama->new(hosts => 'localhost:9999');};
    like($@, qr/All hosts connection refused/, 'Connection fail.');

    done_testing;
};


subtest 'Close connection' => sub {
    my $client = Net::Okuyama->new(hosts => 'localhost:8888');
    $client->close;
    is($client->{sock}, undef);
    is($client->{host}, undef);

    $client = Net::Okuyama->new(hosts => 'localhost:8888');
    is(ref $client, 'Net::Okuyama');
    is($client->{host}, 'localhost:8888');

    done_testing;
};
subtest 'Set/Get/Remove the value of a record' => sub {
    my $client = Net::Okuyama->new(hosts => 'localhost:8888');
    $client->set('foo', 'bar');
    is('bar', $client->get('foo'));

    $client->set('foo' => 'baz');
    is($client->get('foo'), 'baz');

    $client->set('foo', 'foo', ['baz', 'bazz']);
    is($client->get('foo'), 'foo');

    $client->set('foo' => 'bar', ['baz', 'bazz']);
    is($client->get('foo'), 'bar');

    my $ret = $client->remove('foo');
    is($ret, 1);

    $ret = $client->remove('foo');
    is($ret, 0);

    done_testing;
};

subtest 'Get keys by tag' => sub {
    my $client = Net::Okuyama->new(hosts => 'localhost:8888');
    $client->set('foo', 'bar', ['baz', 'bazz']);
    $client->set('bar', 'foo', ['baz']);

    my $ret = $client->get_keys_by_tag('baz');
    is_deeply($ret, ['foo', 'bar']);

    $ret = $client->get_keys_by_tag('bazz');
    is_deeply($ret, ['foo']);

    $ret = $client->get_keys_by_tag('bazz');
    is_deeply($ret, ['foo']);

    $ret = $client->get_keys_by_tag('foo');
    is_deeply($ret, []);

    done_testing;
};

done_testing;
