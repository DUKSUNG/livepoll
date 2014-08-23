#!/usr/bin/perl -w
#
# 2014.08.23 written by HyeokJin
#
# 이 프로그램은 여러명이 모여있는 상황에서
# 설문조사를 진행할 때 설문자의 응답결과를 
# 실시간으로 집계해서 보여주기 위한 웹서비스이다.
#
use strict;
use warnings;
use utf8;
use Mojolicious::Lite;
use DBI qw(:sql_types); # http://www.sqlite.org/datatype3.html

#
# Default Setting 
#
my $progname = 'livepoll';
my $path_tmp = './';
my $fn_db    = ".$progname.db";
my $clients  = {};
my $counter  = 0;

#
# Initialize DB
#
my $dbh = DBI->connect("dbi:SQLite:dbname=$path_tmp/$fn_db", undef, undef, { AutoCommit => 1, RaiseError => 1, sqlite_see_if_its_a_number => 1,}) or die "Can't connect $path_tmp/$fn_db: $!\n";

# SETTING PRAGMA
$dbh->do("PRAGMA foreign_keys = ON" ) or die DBI::errstr; # For Foreign keys.
$dbh->do("PRAGMA synchronous = OFF" ) or die DBI::errstr; # For Performance.
$dbh->do("PRAGMA cache_size = 80000") or die DBI::errstr; # 80MB for DB cache.

# SETTING DB Handle Attributes
$dbh->{sqlite_unicode} = 1; 

# INIT Table
$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_info (
		livepoll_info_id INTEGER PRIMARY KEY AUTOINCREMENT,
		regdate DATE DEFAULT (datetime('now','localtime')),
		description TEXT
	)
}) or die DBI::errstr;

$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_item (
		livepoll_item_id INTEGER PRIMARY KEY AUTOINCREMENT,
		info_id INTEGER NOT NULL,
		regdate DATE DEFAULT (datetime('now','localtime')),
		subject TEXT NOT NULL,
		FOREIGN KEY(info_id) REFERENCES livepoll_info(livepoll_info_id)
	)
}) or die DBI::errstr;

$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_response (
		livepoll_resp_id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		regdate DATE DEFAULT (datetime('now','localtime')),
		subject TEXT NOT NULL,
		sequence INTEGER NOT NULL,
		count INTEGER DEFAULT 0,
		FOREIGN KEY(item_id) REFERENCES livepoll_info(livepoll_item_id)
	)
}) or die DBI::errstr;

$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_comment (
		livepoll_comment_id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		regdate DATE DEFAULT (datetime('now','localtime')),
		comment TEXT NOT NULL,
		FOREIGN KEY(item_id) REFERENCES livepoll_info(livepoll_item_id)
	)
}) or die DBI::errstr;

#
# 기본 페이지
#
get '/' => sub {
	my $c = shift;
	$c->render(text => 'Please visit our site -> <b><a href=https://github.com/DUKSUNG/livepoll/>https://github.com/DUKSUNG/livepoll/</a></b>');
	closer();
};

#
# 관리자 영역
#
get '/livepoll/admin' => sub {
	my $c = shift;
	my $title = "$progname - Wrong Access!!";
	$c->render('admin', title => $title);
	closer();
};

get '/livepoll/counter' => sub {
	my $c = shift;
	my $title = "$progname - 카운터 확인 : $counter";
	$c->render('counter', title => $title);
	closer();
};

get '/livepoll/admin/poll/list' => sub {
	my $c = shift;
	my $title = "$progname - 설문조사 리스트";
	$c->render('admin.poll.list', title => $title);
	closer();
};

get '/livepoll/admin/poll/add' => sub {
	my $c = shift;
	my $title = "$progname - 설문조사 리스트 추가";
	$c->render('admin.poll.add', title => $title);
	closer();
};

get '/livepoll/admin/poll/rm' => sub {
	my $c = shift;
	my $title = "$progname - 설문조사 리스트 삭제";
	$c->render('admin.poll.rm', title => $title);
	closer();
};

get '/livepoll/admin/poll/edit' => sub {
	my $c = shift;
	my $title = "$progname - 설문조사 리스트 수정";
	$c->render('admin.poll.edit', title => $title);
	closer();
};

get '/livepoll/admin/poll/view' => sub {
	my $c = shift;
	my $title = "$progname - 설문조사 리스트 상세보기";
	$c->render('admin.poll.view', title => $title);
	closer();
};

#
# 설문자 영역
#
get '/livepoll/respondent' => sub {
	my $c = shift;
	my $title = "$progname - 응답자 선택 화면";
	$c->render('respondent', title => $title);
	closer();
};

#
# 집계화면 영역
#

get '/livepoll/screen' => sub {
	my $c = shift;
	my $title = "$progname - 집계 화면";
	$c->render('screen', title => $title);
};

app->start;

sub closer {
	$counter++;
}

__DATA__

@@ admin.html.ep
<%= $title %>

@@ counter.html.ep
<%= $title %>

@@ admin.poll.list.html.ep
<%= $title %>

@@ admin.poll.add.html.ep
<%= $title %>

@@ admin.poll.rm.html.ep
<%= $title %>

@@ admin.poll.edit.html.ep
<%= $title %>

@@ admin.poll.view.html.ep
<%= $title %>

@@ respondent.html.ep
<%= $title %>

@@ screen.html.ep
<%= $title %>


