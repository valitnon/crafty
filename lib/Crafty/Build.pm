package Crafty::Build;
use Moo;

use Data::UUID;
use Time::Moment;
use Crafty::Log;

has 'uuid', is => 'ro', builder => '_generate_id', predicate => 1;
has 'project', is => 'ro', required => 1, predicate => 1;
has 'status', is => 'rw', default => sub { 'N' }, predicate => 1;

has 'created',  is => 'rw', predicate => 1;
has 'started',  is => 'rw', predicate => 1;
has 'finished', is => 'rw', predicate => 1;

has 'rev',     is => 'ro', required => 1, predicate => 1;
has 'ref',     is => 'ro', required => 1, predicate => 1;
has 'author',  is => 'ro', required => 1, predicate => 1;
has 'message', is => 'ro', required => 1, predicate => 1;

has 'pid',     is => 'rw', predicate => 1;
has 'version', is => 'rw', predicate => 1;

sub columns {
    return (
        'project',
        'uuid',

        'status',

        'created',
        'started',
        'finished',

        'rev',
        'ref',
        'author',
        'message',

        'pid',
        'version',
    );
}

sub is_new  { !!shift->{is_new} }
sub not_new { delete shift->{is_new} }

sub duration {
    my $self = shift;
    my ($from, $to) = @_;

    return 0 unless my $started = $self->started;
    my $finished = $self->finished || $self->_now;

    my $duration = 0;

    eval {
        my $finished_moment = Time::Moment->from_string($finished, lenient => 1);
        my $started_moment  = Time::Moment->from_string($started,  lenient => 1);

        $duration =
          ($finished_moment->epoch +
              $finished_moment->microsecond / 1000000 -
              $started_moment->epoch +
              $started_moment->microsecond / 1000000);
    } or do {
        warn "$@";
    };

    return $duration;
}

sub status_display {
    my $self = shift;

    return {
        'N' => 'default',
        'I' => 'default',
        'P' => 'default',
        'L' => 'default',
        'S' => 'success',
        'E' => 'danger',
        'F' => 'danger',
        'C' => 'danger',
        'K' => 'danger',
    }->{ $self->status };
}

sub status_name {
    my $self = shift;

    return {
        'N' => 'New',
        'I' => 'Preparing',
        'L' => 'Locked',
        'P' => 'Running',
        'S' => 'Success',
        'E' => 'Error',
        'F' => 'Failure',
        'C' => 'Canceled',
        'K' => 'Killed',
    }->{ $self->status };
}

sub is_cancelable {
    my $self = shift;

    return $self->status eq 'I' || $self->status eq 'P' || $self->status eq 'N';
}

sub is_restartable {
    my $self = shift;

    return $self->status ne 'I' && $self->status ne 'P' && $self->status ne 'N';
}

sub finish {
    my $self = shift;
    my ($new_status) = @_;

    $self->status($new_status);
    $self->finished($self->_now);

    return 1;
}

sub init {
    my $self = shift;

    unless ($self->status eq 'N') {
        Crafty::Log->error('Build %s is in invalid status for init: %s', $self->uuid, $self->status);
        return;
    }

    $self->status('I');
    $self->created($self->_now);

    return 1;
}

sub start {
    my $self = shift;

    unless ($self->status eq 'I' || $self->status eq 'L') {
        Crafty::Log->error('Build %s is in invalid status for start: %s', $self->uuid, $self->status);
        return;
    }

    $self->status('P');
    $self->started($self->_now);
    $self->finished('');

    return 1;
}

sub restart {
    my $self = shift;

    unless ($self->is_restartable) {
        Crafty::Log->error('Build %s is in invalid status for restart: %s', $self->uuid, $self->status);
        return;
    }

    $self->pid(0);
    $self->status('I');
    $self->started('');
    $self->finished('');

    return 1;
}

sub cancel {
    my $self = shift;

    unless ($self->is_cancelable) {
        Crafty::Log->error('Build %s is in invalid status for cancel: %s', $self->uuid, $self->status);
        return;
    }

    $self->status('C');
    $self->finished($self->_now);

    return 1;
}

sub to_store {
    my $self = shift;

    my $store = { uuid => $self->uuid };

    foreach my $column ($self->columns) {
        my $predicate = 'has_' . $column;
        next unless $self->$predicate;

        $store->{$column} = $self->$column;
    }

    return $store;
}

sub to_hash {
    my $self = shift;

    return {
        %{ $self->to_store },

        status_name    => $self->status_name,
        status_display => $self->status_display,

        is_new         => $self->is_new,
        is_cancelable  => $self->is_cancelable,
        is_restartable => $self->is_restartable,

        duration => $self->duration,
    };
}

sub to_env {
    my $self = shift;

    my $hash = $self->to_hash;

    return { map { "CRAFTY_BUILD_" . uc($_) => $hash->{$_} } keys %$hash };
}

sub _now {
    return Time::Moment->now->strftime('%F %T%f%z');
}

sub _generate_id {
    my $self = shift;

    $self->{is_new} = 1;

    my $id = my $uuid = Data::UUID->new;
    return lc($uuid->to_string($uuid->create));
}

1;
