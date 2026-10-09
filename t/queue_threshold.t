#!/usr/bin/perl

# Functional test for the queue directive's threshold= parameter.
#
# Once the queue has filled up it stays closed - every request that
# cannot get a server immediately is answered 503 - until it has drained
# below threshold percent of its size. This checks both halves: that a
# place freeing up is not enough to reopen the queue while it is still
# above the threshold, and that it does reopen once below it.

###############################################################################

use warnings;
use strict;

use Test::More;
use IO::Select;
use IO::Socket::INET;
use IO::Socket::UNIX;
use Socket qw/ SOCK_STREAM /;
use Time::HiRes qw/ time /;

BEGIN {
	use FindBin;
	chdir($FindBin::Bin);
	$ENV{TEST_NGINX_BINARY} ||= '../../nginx/objs/nginx';
}

use lib '../../nginx-tests/lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $module = "$FindBin::Bin/../../nginx/objs/ngx_http_upstream_queue_module.so";

if (!-e $module) {
	Test::More::plan(skip_all => "$module not built");
}

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(5);

my $sock = $t->testdir() . '/b.sock';

$t->write_file_expand('nginx.conf', <<"EOF");

%%TEST_GLOBALS%%

load_module $module;

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream backend {
        server unix:$sock max_conns=1 max_fails=0;
        queue 4 timeout=10s threshold=50;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://backend;
            proxy_connect_timeout 15s;
            proxy_read_timeout 15s;
        }
    }
}

EOF

$t->run_daemon(\&hold_backend, $sock);
$t->waitforfile($sock) or die "backend did not start\n";

$t->run();

###############################################################################

# holder takes the only slot; q1..q4 fill the queue (4 of 4).

my $holder = send_request('/holder');
select(undef, undef, undef, 0.2);

my @q;
for my $i (1 .. 4) {
	push @q, send_request("/q$i");
	select(undef, undef, undef, 0.1);
}

is(scalar(grep { ready($_) } @q), 0,
	'requests up to the queue size are queued');

# Queue is full: the next one closes it and is answered 503.

like(read_response(send_request('/full'), 2), qr!^HTTP/1\.[01] 503 !,
	'queue full: extra request gets 503');

# One queued client goes away: 3 of 4 queued, still above the 50%
# threshold, so the queue stays closed even though a place is free.

(shift @q)->close();
select(undef, undef, undef, 0.3);

like(read_response(send_request('/above'), 2), qr!^HTTP/1\.[01] 503 !,
	'above the threshold: still 503 although the queue has a free place');

# Two more go away: 1 of 4 queued, below the threshold - the queue
# reopens and the next request is queued again instead of rejected.

(shift @q)->close();
(shift @q)->close();
select(undef, undef, undef, 0.3);

my $r = send_request('/below');
ok(!ready($r, 0.5), 'below the threshold: request is queued again');

# And it stays open while it refills, up to the full size.

my $r2 = send_request('/refill');
ok(!ready($r2, 0.5), 'reopened queue keeps accepting until full again');

###############################################################################

sub ready {
	my ($s, $timeout) = @_;
	my @ready = IO::Select->new($s)->can_read($timeout || 0);
	return scalar @ready;
}

sub send_request {
	my ($uri) = @_;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port(8080),
	) or die "Can't connect to nginx: $!\n";

	$s->autoflush(1);
	$s->syswrite(<<EOF);
GET $uri HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
EOF

	return $s;
}

sub read_response {
	my ($s, $timeout) = @_;
	my $resp = '';
	my $deadline = time() + $timeout;

	while (time() < $deadline) {
		my $sel = IO::Select->new($s);
		last unless $sel->can_read($deadline - time());
		my $n = sysread($s, my $chunk, 65536);
		last if !$n;
		$resp .= $chunk;
	}

	return $resp;
}

sub hold_backend {
	my ($path) = @_;

	unlink $path;

	my $server = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Local => $path,
		Listen => 5,
	) or die "Can't create unix listening socket: $!\n";

	my $client = $server->accept()
		or die "Can't accept unix connection: $!\n";

	# Holds the only slot for the rest of the test; never answers.
	select(undef, undef, undef, 20);
	exit 0;
}

###############################################################################
