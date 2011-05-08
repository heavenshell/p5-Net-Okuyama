package Net::Okuyama;
use strict;
use warnings;
use 5.00800;
use IO::Socket::INET;
use List::Util 'shuffle';
use Scalar::Util qw/looks_like_number/;
use MIME::Base64;
use Data::Dumper;

our $VERSION = '0.01';

my %CONST = (
    DATA_DELIMITER   => ',',
    TAG_DELIMITER    => ':',
    BLANK_STRING     => '(B)',
    TRANSACTION_CODE => '0',
);

my %PREFIX_ID = (
    ID_INIT          => '0',
    ID_SET           => '1',
    ID_GET           => '2',
    ID_TAG_SET       => '3',
    ID_TAG_GET       => '4',
    ID_REMOVE        => '5',
    ID_ADD           => '6',
    ID_PLAY_SCRIPT   => '8',
    ID_UPDATE_SCRIPT => '9',
    ID_GETS          => '15',
    ID_CAS           => '16',
);

sub new {
    my $class = shift;
    my %args  = @_== 1 ? %{$_[0]} : @_;
    my @hosts = ();
    $args{hosts} = $args{hosts} || 'localhost:8888';
    if (ref \$args{hosts} eq 'SCALAR') {
        @hosts = [$args{hosts}];
    } else {
        @hosts = $args{hosts};
    }

    my $self = bless {
        host     => undef,
        sock     => undef,
        timout   => $args{timeout} || 10,
        size     => 2560,
        max_size => 2560,
        debug    => $args{debug} || $ENV{OKUYAMA_DEBUG} || 0,
    }, $class;

    if (@hosts) {
        $self->auto_connect(@hosts);
    }

    return $self;
}

sub connect {
    my($self, $host) = @_;

    my $debug = $self->{debug};
    warn "Try to connect to $host" if $debug;
    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        Proto    => 'tcp',
        TimeOut  => $self->{timeout} || 10,
    ) || 0;
    return if $sock == 0;

    delete $self->{sock};
    delete $self->{host};
    $self->{sock} = $sock;
    $self->{host} = $host;

    my $command  = $PREFIX_ID{ID_INIT} . $CONST{DATA_DELIMITER} . "\n";
    my $response = $self->_parse(
        $self->_send($command)->_recieve, $PREFIX_ID{ID_INIT}
    );

    if ($response->[1] eq 'true') {
        $self->{size}     = $response->[2];
        $self->{max_size} = $response->[2];
    } else {
        return 0;
    }

    warn "Connected to $host" if $debug;
    return $sock;
}

sub auto_connect {
    my($self, $args) = @_;

    # Fail to connect, try to connect another host.
    my @hosts = shuffle(@{$args});
    my $sock  = undef;
    while ((my $cnt = @hosts) > 0) {
        $sock = $self->connect(shift @hosts);
        if ($sock) {
            last;
        }
    }
    if (!$sock) {
        Carp::croak('All hosts connection refused.');
    }

    return 1;
}

sub close {
    my $self = shift;

    close(delete $self->{sock}) || Carp::croak("Can't close socket: $!");
    delete $self->{sock};
    delete $self->{host};
    $self->{size}     = 2560;
    $self->{max_size} = 2560;
}

sub get {
    my($self, $key) = @_;

    my $response = $self->_get($key, $PREFIX_ID{ID_GET});
    return $response->[1];
}

sub set {
    my($self, $key, $value, $tags, $version) = @_;

    return $self->_set($key, $value, $PREFIX_ID{ID_SET}, $tags, $version);
}

sub remove {
    my($self, $key) = @_;

    my $debug    = $self->{debug};
    my $command  = $PREFIX_ID{ID_REMOVE} . $CONST{DATA_DELIMITER}
                 . encode_base64($key, '') . $CONST{DATA_DELIMITER}
                 . $CONST{TRANSACTION_CODE} . "\n";

    my $response = $self->_parse(
        $self->_send($command)->_recieve, $PREFIX_ID{ID_REMOVE}
    );

    if ($response->[1] eq 'true') {
        if ($debug) {
            if ($response->[2] eq $CONST{BLANK_STRING}) {
                warn "[RECV] BLANK STRING ";
            } else {
                my $data = decode_base64($response->[2]);
                warn "[RECV] $data ";
            }
        }
        return 1;
    } elsif ($response->[1] eq 'false' || $response->[1] eq 'error') {
        warn "[RECV] $response->[1] " if $debug;
    } else {
        Carp::croak(sprintf 'Unknown response(%s) return.', $response->[2]);
    }

    return 0;
}

sub get_keys_by_tag {
    my($self, $tag) = @_;

    my $debug    = $self->{debug};
    my $return   = 'false';
    my $command  = $PREFIX_ID{ID_TAG_SET} . $CONST{DATA_DELIMITER}
                 . encode_base64($tag, '') . $CONST{DATA_DELIMITER}
                 . $CONST{TRANSACTION_CODE} . $return . "\n";

    my $response = $self->_parse(
        $self->_send($command)->_recieve, $PREFIX_ID{ID_TAG_GET}
    );

    if ($response->[1] eq 'true') {
        my $data = $response->[2];
        if ($data eq $CONST{BLANK_STRING}) {
            return [];
        }

        my @keys = map {decode_base64($_)} split /$CONST{TAG_DELIMITER}/, $data;
        return \@keys;
    } elsif ($response->[1] eq 'false') {
        return [];
    }

    Carp::croak('Unknown response return.');
}

sub _get {
    my($self, $key, $type) = @_;

    my $debug    = $self->{debug};
    my $command  = $type . $CONST{DATA_DELIMITER} . encode_base64($key, '') . "\n";
    my $response = $self->_parse($self->_send($command)->_recieve, $type);
    my $result   = [$response->[1]];
    if ($response->[1] eq 'true') {
        if ($response->[2] eq $CONST{BLANK_STRING}) {
            push @{$result}, '';
        } else {
            push @{$result}, decode_base64($response->[2]);
        }
        if ($type eq $PREFIX_ID{ID_GETS}) {
            push @{$result}, $response->[3];
        }
    } elsif ($response->[1] eq 'false' || $response->[1] eq 'error') {
        push @{$result}, undef;
        push @{$result}, $response->[2];
    } else {
        Carp::croak(sprintf 'Unknown response(%s) return.', $response->[2]);
    }

    return $result;
}

sub _set {
    my($self, $key, $value, $type, $tags, $version) = @_;

    my $debug = $self->{debug};
    my $tpl   = '%s(%s) size is overflow, allow max size is %s.';
    if (length($key) > $self->{max_size}) {
        Carp::croak(sprintf $tpl, 'Key string', $key, $self->{max_size});
    }

    if ($value eq '' || !defined $value) {
        $value = $CONST{BLANK_STRING};
    } else {
        if (length($value) > $self->{max_size}) {
            Carp::croak(sprintf 'Values', $value, $self->{max_size});
        }
        $value = encode_base64($value, '');
    }

    $type = $PREFIX_ID{ID_SET} unless defined $type;
    my $command = $type . $CONST{DATA_DELIMITER}
                . encode_base64($key, '') . $CONST{DATA_DELIMITER};
    if ($tags) {
        my $buffer = '';
        for my $tag (@{$tags}) {
            $buffer .= $CONST{TAG_DELIMITER} . encode_base64($tag, '');
        }
        $buffer  =~ s/$CONST{TAG_DELIMITER}//;
        $command .= $buffer;
    } else {
        $command = $command . $CONST{BLANK_STRING};
    }

    $command .= $CONST{DATA_DELIMITER} . $CONST{TRANSACTION_CODE} . $CONST{DATA_DELIMITER} . $value;

    if ($type eq $PREFIX_ID{ID_CAS} && looks_like_number($version)) {
        $command = $command . $CONST{DATA_DELIMITER} . $version;
    }
    $command .= "\n";
    my $response = $self->_parse($self->_send($command)->_recieve, $type);

    if ($response->[1] eq 'true') {
        return $self;
    } elsif ($response->[1] eq 'false') {
        return 0;
    }

    return $self;
}

sub _send {
    my($self, $command) = @_;

    my $debug = $self->{debug};
    my $sock  = $self->{sock} || Carp::croak('Not connected to any server');
    warn "[SEND] $command " if $debug;

    my $len = syswrite $sock, $command, length $command;
    Carp::croak("Could not write to okuyama server: $!") unless $len;

    return $self;
}

sub _recieve {
    my($self, $command) = @_;

    my $debug = $self->{debug};
    my $sock  = $self->{sock};
    my $data  = <$sock>;
    Carp::croak("Error while reading from okuyama server: $!")
        unless defined $data;
    chomp $data;
    warn "[RECV] '$data'" if $debug;

    return $data;
}

sub _parse {
    my($self, $data, $id) = @_;

    my @result = split /,/, $data;
    if ($result[0] eq $id) {
        return \@result;
    }

    Carp::croak('Execute violation of validity.');
}

1;
__END__

=encoding utf8

=head1 NAME

Net::Okuyama - okuyama(Distributed kvs) client library

=head1 SYNOPSIS

    use Net::Okuyama;

    my $client = Net::Okuyama->new(hosts => 'localhost:8888');
    $client->set('foo' => bar');
    $client->get('foo'); # => 'bar'
    $client->remove('foo'); # remove foo


=head1 DESCRIPTION

Okuyama.pm is L<okuyama|http://sourceforge.jp/projects/okuyama/> client library for Perl5.

This module is heavely inspired by L<Redis> and L<Cache::KyotoTycoon>.

=head1 AUTHOR

Shinya Ohyanagi E<lt>sohyanagi AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=over 1

=item L<okuyama|http://sourceforge.jp/projects/okuyama/>

=back

=head1 LICENSE

Copyright (C) Shinya Ohyanagi

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
