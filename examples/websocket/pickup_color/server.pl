#!/usr/bin/env perl
use utf8;
use Mojolicious::Lite;

get '/' => sub {
	my $c = shift;
	$c->render('index');
};

my $clients = {};

websocket '/pickup' => sub {
	my $self = shift;

	$self->inactivity_timeout(0);

	app->log->debug(sprintf 'Client connected: %s', $self->tx);

	my $id = sprintf "%s", $self->tx;
	$clients->{$id} = $self->tx;

	$self->on(message => sub {
			my ($self, $msg) = @_;
			for (keys %$clients) {
				$clients->{$_}->send({json => { text => $msg, }});
			}
		});

	$self->on(finish => sub {
			app->log->debug('Client disconnected');
			delete $clients->{$id};
		});
};

app->start;

__DATA__
@@ index.html.ep
<html>
<head>
<title>WebSocket TEST</title>
<script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
<script type="text/javascript">

$(function () {

	$('#msg').focus();

	var ws = new WebSocket('ws://203.252.219.164:3000/pickup');

	ws.onopen = function () {
		document.getElementById("status").innerHTML = "Connection Opened!";
	};

	ws.onmessage = function (msg) {
		var res = JSON.parse(msg.data);
		document.getElementById("status").innerHTML = "<div style='background-color:" + res.text + "'>This is a Message. HaHaHa!!!</div>";
	};

	$('#msg').keydown(function (e) {
		if (e.keyCode == 13 && $('#msg').val()) {
			ws.send($('#msg').val());
			$('#msg').val('');
		}
	});
});
</script>
<style type="text/css">
</style>
</head>

<body>

<h1>TEST</h1>
<input type="text" id="msg" />
<p><div id=status></div>

</body>
</html>
