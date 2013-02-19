package LML::Config;

use strict;
use warnings;

use LML::Common;

sub new {
    my $class = shift;
    my $self;
    if (ref($_[0]) eq "HASH" ) {
        $self = shift;
    } else {
        my %C = LoadConfig(@_);
        $self  = \%C;
    }
    bless( $self, $class );
    return $self;
}

sub get {
    my ($self,$section,$key) = @_;
    if ( exists( $self->{$section}->{$key} ) ) {
        return $self->{$section}->{$key};
    } else {
        return undef;
    }
}

1;