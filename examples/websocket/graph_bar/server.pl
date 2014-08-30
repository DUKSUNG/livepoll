#!/usr/bin/env perl
use utf8;
use Mojolicious::Lite;
use Data::Dumper;

get '/' => sub {
	my $c = shift;
	$c->render('index');
};

my $clients = {};

websocket '/tiktok' => sub {
	my $self = shift;

	$self->inactivity_timeout(0);

	my $id = sprintf "%s", $self->tx;
	$clients->{$id} = $self->tx;

	app->log->debug('Count of Clients : ' . keys %{ $clients });

	$self->on(message => sub {
			my ($self, $msg) = @_;

			my $name;
			my $mode;

			if ( $msg =~ /^([+-])(.+)/ ) {
				$mode = $1."1";
				$name = $2;
				app->log->debug("mode: $mode, name: $name");
				for (keys %$clients) {
					$clients->{$_}->send({json => { mode => $mode, name => $name }});
				}
			}
		});

	$self->on(finish => sub {
			delete $clients->{$id};
			app->log->debug('Client disconnected : ' . keys %{$clients});
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

	var ws = new WebSocket('ws://203.252.219.164:3000/tiktok');

	ws.onopen = function () {
		document.getElementById("status").innerHTML = "Connection Opened!";
	};

	ws.onmessage = function (msg) {
		var res = JSON.parse(msg.data);

		var size = document.getElementById(res.name).style.paddingRight;
		if ( !size ) { size = 0; }

		document.getElementById("status").innerHTML = "mode: " + res.mode + ", name: " + res.name + ", size: " + size;

		size = parseInt(size, 0);
		if ( res.mode > 0 ) {
			size = size + 10;
		} else {
			size = size - 10;
		}

		document.getElementById(res.name).style.paddingRight = size;
	};

	$('#no1_add').click(function (e)   { ws.send("+graph_1" ); });
	$('#no1_minus').click(function (e) { ws.send("-graph_1" ); });

	$('#no2_add').click(function (e)   { ws.send("+graph_2" ); });
	$('#no2_minus').click(function (e) { ws.send("-graph_2" ); });

	$('#no3_add').click(function (e)   { ws.send("+graph_3" ); });
	$('#no3_minus').click(function (e) { ws.send("-graph_3" ); });

	$('#no4_add').click(function (e)   { ws.send("+graph_4" ); });
	$('#no4_minus').click(function (e) { ws.send("-graph_4" ); });

});
</script>
<style type="text/css">
#graph_1 { background-color: red; padding-right: 1 }
#graph_2 { background-color: red; padding-right: 1 }
#graph_3 { background-color: red; padding-right: 1 }
#graph_4 { background-color: red; padding-right: 1 }
</style>
</head>

<body>

<h1>TEST</h1>

<div id=status>Not connected</div></p>

<input type="submit" id="no1_add" value="+">
<input type="submit" id="no1_minus" value="-">
1. <span id=graph_1>&nbsp;</span></br>

<input type="submit" id="no2_add" value="+">
<input type="submit" id="no2_minus" value="-">
2. <span id=graph_2>&nbsp;</span></br>

<input type="submit" id="no3_add" value="+">
<input type="submit" id="no3_minus" value="-">
3. <span id=graph_3>&nbsp;</span></br>

<input type="submit" id="no4_add" value="+">
<input type="submit" id="no4_minus" value="-">
4. <span id=graph_4>&nbsp;</span></br>

</body>
</html>
