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
my $synctest  = {};
my $response  = {};
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
	CREATE TABLE IF NOT EXISTS livepoll_state (
		info_id INTEGER NOT NULL,
		item_id INTEGER NOT NULL
	)
}) or die DBI::errstr;

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
		sequence INTEGER DEFAULT 1,
		allowcomment INTEGER DEFAULT 0,
		FOREIGN KEY(info_id) REFERENCES livepoll_info(livepoll_info_id)
	)
}) or die DBI::errstr;

$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_item_select (
		livepoll_item_select_id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		regdate DATE DEFAULT (datetime('now','localtime')),
		subject TEXT NOT NULL,
		sequence INTEGER DEFAULT 1,
		count INTEGER DEFAULT 0,
		FOREIGN KEY(item_id) REFERENCES livepoll_item(livepoll_item_id)
	)
}) or die DBI::errstr;

$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_item_check (
		livepoll_item_check_id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		regdate DATE DEFAULT (datetime('now','localtime')),
		subject TEXT NOT NULL,
		sequence INTEGER DEFAULT 1,
		count INTEGER DEFAULT 0,
		FOREIGN KEY(item_id) REFERENCES livepoll_item(livepoll_item_id)
	)
}) or die DBI::errstr;


$dbh->do(q{
	CREATE TABLE IF NOT EXISTS livepoll_item_comment (
		livepoll_comment_id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		regdate DATE DEFAULT (datetime('now','localtime')),
		comment TEXT NOT NULL,
		FOREIGN KEY(item_id) REFERENCES livepoll_item(livepoll_item_id)
	)
}) or die DBI::errstr;

#
# 기본 페이지
#
get '/' => sub {
	my $c = shift;
	$c->render(text => '<a href=/livepoll/synctest><b>동기화 테스트</b></a>');
	#$c->render(text => '<a href=/livepoll/respondent><b>설문 시작하기</b></a>');
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
	my $title = "$progname - 설문주제 리스트";
	my $content = "";

	my $stmt_select = q{SELECT livepoll_info_id, description, regdate FROM livepoll_info order by livepoll_info_id};
	my $sth = $dbh->prepare($stmt_select);
	$sth->execute();
	while ( my ($info_id, $desc, $date) = $sth->fetchrow_array ) {
		$content .= "<small>$date</small> <small><a href='/livepoll/admin/poll/edit?info_id=$info_id'>수정</a>, <a href='/livepoll/admin/poll/rm?info_id=$info_id'>삭제</a></small> <a href='/livepoll/admin/poll/view?info_id=$info_id'>$desc</a> [<a href=/livepoll/screen?info_id=$info_id>SCREEN</a>]<br>";
	}
	$c->render('admin.poll.list', header => header(), footer => footer(), title => $title, content => $content);

	closer();
};

get '/livepoll/admin/poll/add' => sub {
	my $c = shift;
	my $desc = $c->param("desc") || "";
	my $title = "$progname - 설문주제 추가";

	if ( $desc ) {
		my $stmt_insert = sprintf("INSERT INTO livepoll_info(description) VALUES (%s)", $dbh->quote($desc));
		$dbh->do($stmt_insert) or die DBI::errstr;
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	} else {
		$c->render('admin.poll.add', header => header(), footer => footer(), title => $title);
	}
	closer();
};

get '/livepoll/admin/poll/edit' => sub {
	my $c = shift;
	my $desc = $c->param("desc");
	my $info_id = $c->param("info_id") || "";
	my $title = "$progname - 설문주제 수정";

	if ( $info_id && $desc ) {
		my $stmt_update = sprintf("UPDATE livepoll_info SET description=%s WHERE livepoll_info_id=$info_id", $dbh->quote($desc));
		$dbh->do($stmt_update);
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');

	} elsif ( $info_id ) {
		my $stmt_select = "SELECT description FROM livepoll_info WHERE livepoll_info_id=$info_id";
		my $sth = $dbh->prepare($stmt_select);
		$sth->execute();

		my ($desc) = $sth->fetchrow_array;

		$c->render('admin.poll.edit', header => header(), footer => footer(), title => $title, info_id => $info_id, desc => $desc);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}

	closer();
};

get '/livepoll/admin/poll/rm' => sub {
	my $c = shift;
	my $check = $c->param('check') || 0;
	my $info_id = $c->param('info_id') || 0;

	if ( $check && $info_id ) {
		#
		# 삭제순서
		# select item_id
		# 	delete livepoll_response
		#	delete livepoll_comment
		# delete livepoll_item
		# delete livepoll_info
		#
		my $stmt_select = "SELECT livepoll_item_id FROM livepoll_item WHERE info_id=$info_id";
		my $sth = $dbh->prepare($stmt_select);
		$sth->execute();

		while ( my ($item_id) = $sth->fetchrow_array ) {
			foreach my $table ( ("livepoll_comment", "livepoll_response") ) {
				$dbh->do("DELETE FROM $table WHERE item_id=$item_id") or die DBI::errstr;
			}
		}

		$dbh->do("DELETE FROM livepoll_item WHERE info_id=$info_id") or die DBI::errstr;
		$dbh->do("DELETE FROM livepoll_info WHERE livepoll_info_id=$info_id") or die DBI::errstr;

		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	} elsif ( $info_id ) {
		my $title = "$progname - 설문주제 삭제";
		$c->render('admin.poll.rm', header => header(), footer => footer(), title => $title, info_id => $info_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/poll/view' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");

	if ( $info_id ) {
		#
		# select desc
		# LOOP:
		#	select item_id
		#		LOOP:
		#			select resp_id
		#			select comment_id
		#
		my $sth = $dbh->prepare("SELECT description FROM livepoll_info WHERE livepoll_info_id=$info_id");
		$sth->execute();
		my ($desc) = $sth->fetchrow_array or die "Can't get desc. please check info_id: $info_id";

		my $title = "$progname - '$desc' 상세보기";
		my $content = "";

		$sth = $dbh->prepare("SELECT sequence, livepoll_item_id, regdate, subject, allowcomment FROM livepoll_item WHERE info_id=$info_id ORDER BY sequence");
		$sth->execute();
		while ( my ($seq, $item_id, $date, $subj, $allowcomment) = $sth->fetchrow_array ) {
			$content .= "No.$seq : <small>$date</small> <small><a href='/livepoll/admin/item/move?type=livepoll_item&mode=up&item_id=$item_id&info_id=$info_id'>UP</a>, <a href='/livepoll/admin/item/move?type=livepoll_item&mode=down&item_id=$item_id&info_id=$info_id'>DOWN</a>, <a href='/livepoll/admin/item/edit?item_id=$item_id&info_id=$info_id'>수정</a>, <a href='/livepoll/admin/item/rm?item_id=$item_id&info_id=$info_id'>삭제</a>, 문항추가(<a href='/livepoll/admin/item/add/select?item_id=$item_id&info_id=$info_id'>선택</a>, <a href='/livepoll/admin/item/add/check?item_id=$item_id&info_id=$info_id'>다중</a>, <a href='/livepoll/admin/item/add/comment?item_id=$item_id&info_id=$info_id'>기타</a>)</small> $subj <br>";

			#
			# SELECT
			#
			my $sth2 = $dbh->prepare("SELECT livepoll_item_select_id, sequence, subject, count FROM livepoll_item_select WHERE item_id=$item_id ORDER BY sequence");
			$sth2->execute();
			while ( my ($select_id, $seq, $subject, $count) = $sth2->fetchrow_array ) {
				$content .= "$seq : <small><a href='/livepoll/admin/item/move?type=livepoll_item_select&mode=up&select_id=$select_id&item_id=$item_id&info_id=$info_id'>UP</a>, <a href='/livepoll/admin/item/move?type=livepoll_item_select&mode=down&item_id=$item_id&select_id=$select_id&info_id=$info_id'>DOWN</a>, <a href='/livepoll/admin/item/edit/select?item_id=$item_id&info_id=$info_id&select_id=$select_id'>수정</a>, <a href='/livepoll/admin/item/rm/select?item_id=$item_id&info_id=$info_id&select_id=$select_id'>삭제</a>, <a href='/livepoll/admin/item/reset/select?item_id=$item_id&info_id=$info_id&select_id=$select_id'>값초기화</a>, <a href='/livepoll/admin/item/choice/select?item_id=$item_id&info_id=$info_id&select_id=$select_id'>+1</a>, <a href='/livepoll/admin/item/cancel/select?item_id=$item_id&info_id=$info_id&select_id=$select_id'>-1</a></small> $subject, </br><span style='background-color: red; padding-right: ${count}0'>&nbsp;</span>$count</p>";
			}

			#
			# CHECK
			#
			$sth2 = $dbh->prepare("SELECT livepoll_item_check_id, sequence, subject, count FROM livepoll_item_check WHERE item_id=$item_id ORDER BY sequence");
			$sth2->execute();
			while ( my ($check_id, $seq, $subject, $count) = $sth2->fetchrow_array ) {
				$content .= "$seq : <small><a href='/livepoll/admin/item/move?type=livepoll_item_check&mode=up&check_id=$check_id&item_id=$item_id&info_id=$info_id'>UP</a>, <a href='/livepoll/admin/item/move?type=livepoll_item_check&mode=down&item_id=$item_id&check_id=$check_id&info_id=$info_id'>DOWN</a>, <a href='/livepoll/admin/item/edit/check?item_id=$item_id&info_id=$info_id&check_id=$check_id'>수정</a>, <a href='/livepoll/admin/item/rm/check?item_id=$item_id&info_id=$info_id&check_id=$check_id'>삭제</a>, <a href='/livepoll/admin/item/reset/check?item_id=$item_id&info_id=$info_id&check_id=$check_id'>값초기화</a>, <a href='/livepoll/admin/item/choice/check?item_id=$item_id&info_id=$info_id&check_id=$check_id'>+1</a>, <a href='/livepoll/admin/item/cancel/check?item_id=$item_id&info_id=$info_id&check_id=$check_id'>-1</a></small> $subject,  </br><span style='background-color: red; padding-right: ${count}0'>&nbsp;</span>$count</p>";
			}

			#
			# COMMENT
			#
			if ( $allowcomment ) {
				$sth2 = $dbh->prepare("SELECT livepoll_comment_id, comment FROM livepoll_item_comment WHERE item_id=$item_id");
				$sth2->execute();
				while ( my ($comment_id, $comment) = $sth2->fetchrow_array ) {
					$content .= "- $comment<br>";
				}
			}

			$content .= '<p>';
		}

		$c->render('admin.poll.view', header => header(), footer => footer(), title => $title, content => $content, info_id => $info_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/add' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");
	my $subject = $c->param("subject");
	my $title = "$progname - 설문문항 추가";

	if ( $info_id && $subject ) {
		# sequence 값 구하기
		my $sth = $dbh->prepare("SELECT MAX(sequence) FROM livepoll_item WHERE info_id=$info_id");
		$sth->execute();
		my ($max_sequence) = $sth->fetchrow_array;
		$max_sequence++;

		my $stmt_insert = sprintf("INSERT INTO livepoll_item(info_id, subject, sequence) VALUES (%d, %s, %d)", $info_id, $dbh->quote($subject), $max_sequence);
		$dbh->do($stmt_insert) or die DBI::errstr;
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} else {
		$c->render('admin.item.add', header => header(), footer => footer(), title => $title, info_id => $info_id);
	}
	closer();
};

get '/livepoll/admin/item/edit' => sub {
	my $c = shift;
	my $item_id = $c->param("item_id");
	my $info_id = $c->param("info_id");
	my $subject = $c->param("subject");
	my $title = "$progname - 설문문항 수정";

	if ( $info_id && $item_id && $subject ) {
		my $stmt_update = sprintf("UPDATE livepoll_item SET subject=%s WHERE livepoll_item_id=$item_id", $dbh->quote($subject));
		$dbh->do($stmt_update);
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");

	} elsif ( $info_id && $item_id ) {
		my $stmt_select = "SELECT subject FROM livepoll_item WHERE livepoll_item_id=$item_id";
		my $sth = $dbh->prepare($stmt_select);
		$sth->execute();

		my ($subject) = $sth->fetchrow_array;

		$c->render('admin.item.edit', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id, subject => $subject);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}

	closer();
};

get '/livepoll/admin/item/move' => sub {
	my $c = shift;
	my $mode = $c->param("mode");
	my $type = $c->param("type");
	my $item_id = $c->param("item_id");
	my $info_id = $c->param("info_id");
	my $check_id = $c->param("check_id");
	my $select_id = $c->param("select_id");

	if ( $info_id && $mode && $type && ($item_id || $check_id || $select_id) ) {
		my $oper;
		my $AND;
		my $WHERE;

		# check mode & type
		if ( $mode eq "up" ) {
			$oper = "-1";
		} elsif ( $mode eq "down" ) {
			$oper = "+1";
		} else {
			$c->render('admin.item.edit', header => header(), footer => footer(), message => "$mode is not support.");
		}

		if ( $type eq "livepoll_item" ) {
			$AND = "AND info_id=$info_id";
			$WHERE = "WHERE ${type}_id=$item_id";
		} elsif ( $type eq "livepoll_item_select" ) {
			$AND = "AND item_id=$item_id";
			$WHERE = "WHERE ${type}_id=$select_id";
		} elsif ( $type eq "livepoll_item_check" ) {
			$AND = "AND item_id=$item_id";
			$WHERE = "WHERE ${type}_id=$check_id";
		} else {
			$c->render('admin.item.edit', header => header(), footer => footer(), message => "$mode is not support.");
		}

		my $sth = $dbh->prepare("SELECT sequence FROM $type $WHERE");
		$sth->execute();
		my ( $sequence ) = $sth->fetchrow_array;
		if ( defined($sequence) ) {
			my $sth2 = $dbh->prepare("SELECT ${type}_id FROM $type WHERE sequence=$sequence$oper $AND");
			$sth2->execute();
			if ( my ( $item_id_target ) = $sth2->fetchrow_array ) {
				$dbh->do("UPDATE $type SET sequence=$sequence WHERE ${type}_id=$item_id_target");
				$dbh->do("UPDATE $type SET sequence=$sequence$oper $WHERE");
			} else {
				$dbh->do("UPDATE $type SET sequence=$sequence$oper $WHERE");
			}
		}

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id ) {
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}

	closer();
};

get '/livepoll/admin/item/add/select' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");
	my $item_id = $c->param("item_id");
	my $subject = $c->param("subject");
	my $title = "$progname - 선택항목 추가";

	if ( $info_id && $item_id && $subject ) {
		# sequence 값 구하기
		my $sth = $dbh->prepare("SELECT MAX(sequence) FROM livepoll_item_select WHERE item_id=$item_id");
		$sth->execute();
		my ($max_sequence) = $sth->fetchrow_array;
		$max_sequence++;

		my $stmt_insert = sprintf("INSERT INTO livepoll_item_select(item_id, subject, sequence) VALUES (%d, %s, %d)", $item_id, $dbh->quote($subject), $max_sequence);
		$dbh->do($stmt_insert) or die DBI::errstr;
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $item_id ) {
		$c->render('admin.item.add.select', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id);
	} else {
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/list'></meta></html>");
	}
	closer();
};

get '/livepoll/admin/item/edit/select' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");
	my $item_id = $c->param("item_id");
	my $select_id = $c->param("select_id");
	my $subject = $c->param("subject");
	my $title = "$progname - 선택항목 수정";

	if ( $info_id && $item_id && $select_id && $subject ) {
		my $stmt_update = sprintf("UPDATE livepoll_item_select SET subject=%s WHERE livepoll_item_select_id=$select_id", $dbh->quote($subject));
		$dbh->do($stmt_update) or die DBI::errstr;
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $item_id && $select_id ) {
		my $stmt_select = "SELECT subject FROM livepoll_item_select WHERE livepoll_item_select_id=$select_id";
		my $sth = $dbh->prepare($stmt_select);
		$sth->execute();
		my ( $subject ) = $sth->fetchrow_array;
		$c->render('admin.item.edit.select', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id, select_id => $select_id, subject => $subject);
	} else {
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/list'></meta></html>");
	}
	closer();
};

get '/livepoll/admin/item/edit/check' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");
	my $item_id = $c->param("item_id");
	my $check_id = $c->param("check_id");
	my $subject = $c->param("subject");
	my $title = "$progname - 선택항목 수정";

	if ( $info_id && $item_id && $check_id && $subject ) {
		my $stmt_update = sprintf("UPDATE livepoll_item_check SET subject=%s WHERE livepoll_item_check_id=$check_id", $dbh->quote($subject));
		$dbh->do($stmt_update) or die DBI::errstr;
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $item_id && $check_id ) {
		my $stmt_select = "SELECT subject FROM livepoll_item_check WHERE livepoll_item_check_id=$check_id";
		my $sth = $dbh->prepare($stmt_select);
		$sth->execute();
		my ( $subject ) = $sth->fetchrow_array;

		$c->render('admin.item.edit.check', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id, check_id => $check_id, subject => $subject);
	} else {
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/list'></meta></html>");
	}
	closer();
};

get '/livepoll/admin/item/rm/select' => sub {
	my $c = shift;
	my $check = $c->param('check') || 0;
	my $info_id = $c->param('info_id') || 0;
	my $select_id = $c->param('select_id') || 0;

	if ( $check && $info_id && $select_id ) {
		$dbh->do("DELETE FROM livepoll_item_select WHERE livepoll_item_select_id=$select_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $select_id ) {
		my $title = "$progname - 설문항목 삭제";
		$c->render('admin.item.rm.select', header => header(), footer => footer(), title => $title, info_id => $info_id, select_id => $select_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/rm/check' => sub {
	my $c = shift;
	my $check = $c->param('check') || 0;
	my $info_id = $c->param('info_id') || 0;
	my $check_id = $c->param('check_id') || 0;

	if ( $check && $info_id && $check_id ) {
		$dbh->do("DELETE FROM livepoll_item_check WHERE livepoll_item_check_id=$check_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $check_id ) {
		my $title = "$progname - 설문항목 삭제";
		$c->render('admin.item.rm.check', header => header(), footer => footer(), title => $title, info_id => $info_id, check_id => $check_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/reset/check' => sub {
	my $c = shift;
	my $check = $c->param('check') || 0;
	my $info_id = $c->param('info_id') || 0;
	my $check_id = $c->param('check_id') || 0;

	if ( $check && $info_id && $check_id ) {
		$dbh->do("UPDATE livepoll_item_check SET count = 0 WHERE livepoll_item_check_id=$check_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $check_id ) {
		my $title = "$progname - 설문항목 카운트 초기화";
		$c->render('admin.item.reset.check', header => header(), footer => footer(), title => $title, info_id => $info_id, check_id => $check_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/reset/select' => sub {
	my $c = shift;
	my $check = $c->param('check') || 0;
	my $info_id = $c->param('info_id') || 0;
	my $select_id = $c->param('select_id') || 0;

	if ( $check && $info_id && $select_id ) {
		$dbh->do("UPDATE livepoll_item_select SET count = 0 WHERE livepoll_item_select_id=$select_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $select_id ) {
		my $title = "$progname - 설문항목 카운트 초기화";
		$c->render('admin.item.reset.select', header => header(), footer => footer(), title => $title, info_id => $info_id, select_id => $select_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/choice/select' => sub {
	my $c = shift;
	my $info_id = $c->param('info_id') || 0;
	my $select_id = $c->param('select_id') || 0;

	if ( $info_id && $select_id ) {
		$dbh->do("UPDATE livepoll_item_select SET count = count + 1 WHERE livepoll_item_select_id=$select_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/cancel/select' => sub {
	my $c = shift;
	my $info_id = $c->param('info_id') || 0;
	my $select_id = $c->param('select_id') || 0;

	if ( $info_id && $select_id ) {
		$dbh->do("UPDATE livepoll_item_select SET count = count - 1 WHERE livepoll_item_select_id=$select_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/choice/check' => sub {
	my $c = shift;
	my $info_id = $c->param('info_id') || 0;
	my $check_id = $c->param('check_id') || 0;

	if ( $info_id && $check_id ) {
		$dbh->do("UPDATE livepoll_item_check SET count = count + 1 WHERE livepoll_item_check_id=$check_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/cancel/check' => sub {
	my $c = shift;
	my $info_id = $c->param('info_id') || 0;
	my $check_id = $c->param('check_id') || 0;

	if ( $info_id && $check_id ) {
		$dbh->do("UPDATE livepoll_item_check SET count = count - 1 WHERE livepoll_item_check_id=$check_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};

get '/livepoll/admin/item/rm' => sub {
	my $c = shift;
	my $check = $c->param('check') || 0;
	my $info_id = $c->param('info_id') || 0;
	my $item_id = $c->param('item_id') || 0;

	if ( $check && $info_id && $item_id ) {
		#
		# 삭제순서
		# delete livepoll_item_check
		# delete livepoll_item_select
		# delete livepoll_item_comment
		# delete livepoll_item
		#
		$dbh->do("DELETE FROM livepoll_item_select WHERE item_id=$item_id") or die DBI::errstr;
		$dbh->do("DELETE FROM livepoll_item_check WHERE item_id=$item_id") or die DBI::errstr;
		$dbh->do("DELETE FROM livepoll_item_comment WHERE item_id=$item_id") or die DBI::errstr;
		$dbh->do("DELETE FROM livepoll_item WHERE livepoll_item_id=$item_id") or die DBI::errstr;

		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $item_id ) {
		my $title = "$progname - 설문문항 삭제";
		$c->render('admin.item.rm', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id);
	} else {
		$c->render(text => '<html> <meta http-equiv="refresh" content="0; url=/livepoll/admin/poll/list"></meta> </html>');
	}
	closer();
};


get '/livepoll/admin/item/add/check' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");
	my $item_id = $c->param("item_id");
	my $subject = $c->param("subject");
	my $title = "$progname - 다중선택항목 추가";

	if ( $info_id && $item_id && $subject ) {
		# sequence 값 구하기
		my $sth = $dbh->prepare("SELECT MAX(sequence) FROM livepoll_item_check WHERE item_id=$item_id");
		$sth->execute();
		my ($max_sequence) = $sth->fetchrow_array;
		$max_sequence++;

		my $stmt_insert = sprintf("INSERT INTO livepoll_item_check(item_id, subject, sequence) VALUES (%d, %s, %d)", $item_id, $dbh->quote($subject), $max_sequence);
		$dbh->do($stmt_insert) or die DBI::errstr;
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $item_id ) {
		$c->render('admin.item.add.check', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id);
	} else {
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/list'></meta></html>");
	}
	closer();
};

get '/livepoll/admin/item/add/comment' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id");
	my $item_id = $c->param("item_id");
	my $check = $c->param("check");
	my $title = "$progname - 기타항목 추가";

	if ( $info_id && $item_id && $check ) {
		my $stmt_update = "UPDATE livepoll_item SET allowcomment=1 WHERE livepoll_item_id=$item_id";
		$dbh->do($stmt_update) or die DBI::errstr;
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/view?info_id=$info_id'></meta> </html>");
	} elsif ( $info_id && $item_id ) {
		$c->render('admin.item.add.comment', header => header(), footer => footer(), title => $title, info_id => $info_id, item_id => $item_id);
	} else {
		$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/admin/poll/list'></meta></html>");
	}
	closer();
};

#
# 동기화 테스트
#
get '/livepoll/synctest' => sub {
	my $c = shift;
	my $title = "$progname - 동기화 테스트";
	$c->render('synctest', header => header(), footer => footer(), title => $title);
	closer();
};

websocket '/livepoll/websocket/synctest' => sub {
	my $self = shift;

	# 타임아웃 설정하지 않음.
	$self->inactivity_timeout(0);

	# $self->tx == HASHREF;
	my $id = sprintf("%s", $self->tx);
	$clients->{$id} = $self->tx;

	app->log->debug('SYNCTEST: CONNECTED: ' . keys %{ $clients });
	$synctest->{total} = keys %{ $clients };
	$clients->{$id}->send( { json => $synctest });

	$self->on(message => sub {
			my ( $self, $msg ) = @_;
			$synctest->{msg}->{$id} = $msg;
			$synctest->{total} = keys %{ $clients };
			foreach my $key ( %{ $clients } ) {
				$clients->{$key}->send( { json => $synctest });
			}
		});

	$self->on(finish => sub {
			delete $clients->{$id};
			delete $synctest->{msg}->{$id};
			$synctest->{total} = keys %{ $clients };
			app->log->debug('SYNCTEST: DISCONNECTED: ' . keys %{ $clients });
			foreach my $key ( %{ $clients } ) {
				$clients->{$key}->send( { json => $synctest });
			}

		});

};

#
# 동기 그래프
#
websocket '/livepoll/websocket/respondent' => sub {
	my $self = shift;

	# 타임아웃 설정하지 않음.
	$self->inactivity_timeout(0);

	my $info_id = $self->param("info_id") || 1;
	my $item_id = $self->param("item_id") || 1;

	# $self->tx == HASHREF;
	my $id = sprintf("%s", $self->tx);
	$clients->{$id} = $self->tx;

	if ( !$response->{$info_id}->{$item_id}->{graph} ) {
		my $sth;
		#
		# SELECT
		#
		$sth = $dbh->prepare("SELECT sequence, count FROM livepoll_item_select WHERE item_id=$item_id ORDER BY sequence");
		$sth->execute();
		while ( my ($seq, $count) = $sth->fetchrow_array ) {
			$response->{$info_id}->{$item_id}->{graph}->{select}->{$seq} = $count;
		}

		#
		# CHECK
		#
		$sth = $dbh->prepare("SELECT sequence, count FROM livepoll_item_check WHERE item_id=$item_id ORDER BY sequence");
		$sth->execute();
		while ( my ($seq, $count) = $sth->fetchrow_array ) {
			$response->{$info_id}->{$item_id}->{graph}->{select}->{$seq} = $count;
		}

		#
		# COMMENT
		#
		$sth = $dbh->prepare("SELECT livepoll_comment_id, comment FROM livepoll_item_comment WHERE item_id=$item_id");
		$sth->execute();
		while ( my ($comment_id, $comment) = $sth->fetchrow_array ) {
			$response->{$info_id}->{$item_id}->{comment}->{$comment} = 1;
		}
	}

	app->log->debug('RESPONDENT: CONNECTED: ' . keys %{ $clients });
	$response->{$info_id}->{$item_id}->{total} = keys %{ $clients };
	$clients->{$id}->send( { json => $response->{$info_id}->{$item_id} });

	$self->on(message => sub {
			my ( $self, $msg ) = @_;

			my ($oper, $sequence);

			if ( $msg =~ /^([+-])(\d)_(.+)$/ ) {
				$response->{$info_id}->{$item_id}->{graph}->{$3}->{$2} += $1."1";
				$response->{$info_id}->{$item_id}->{graph}->{$3}->{$2} = 0 if $response->{$info_id}->{$item_id}->{graph}->{$3}->{$2} < 0;
			} else {
				$response->{$info_id}->{$item_id}->{comment}->{$msg} = 1 if $msg;
			}

			for (keys %$clients) {
				$clients->{$_}->send({json => $response->{$info_id}->{$item_id}});
			}
		});

	$self->on(finish => sub {
			delete $clients->{$id};
			$response->{$info_id}->{$item_id}->{total} = keys %{ $clients };
			app->log->debug('RESPONDENT: DISCONNECTED: ' . keys %{ $clients });
			foreach my $key ( %{ $clients } ) {
				$clients->{$key}->send( { json => $response->{$info_id}->{$item_id} });
			}
		});
};

#
# 응답화면 영역
#
get '/livepoll/respondent' => sub {
	my $c = shift;

	# 진행 상태 정보 가져오기
	my $sth = $dbh->prepare("SELECT info_id, item_id FROM livepoll_state");
	$sth->execute();
	my ($info_id, $item_id) = $sth->fetchrow_array;
	$info_id = 1 unless $info_id;
	$item_id = 1 unless $item_id;

	my $content = "";
	# 필요한 정보
	# prev item_id
	# next item_id
	# item subject
	# 	select subject, count
	# 	check subject, count
	# comment
	my $sequence;
	my $subject;
	my $allowcomment;
	my $item_id_prev;
	my $item_id_next;
	my $item_subject;
	my $tmp;

	$sth = $dbh->prepare("SELECT allowcomment, sequence FROM livepoll_item WHERE livepoll_item_id = $item_id");
	$sth->execute();
	($allowcomment, $sequence) = $sth->fetchrow_array or die "Can't find sequence from item_id($item_id), info_id($info_id)";

	$sth = $dbh->prepare("SELECT livepoll_item_id, MAX(sequence) FROM livepoll_item WHERE sequence < $sequence AND info_id=$info_id");
	$sth->execute();
	($item_id_prev) = $sth->fetchrow_array;
	$item_id_prev = $item_id unless $item_id_prev;

	$sth = $dbh->prepare("SELECT livepoll_item_id, MIN(sequence) FROM livepoll_item WHERE sequence > $sequence AND info_id=$info_id");
	$sth->execute();
	($item_id_next, $tmp) = $sth->fetchrow_array;
	$item_id_next = $item_id unless $item_id_next;

	$sth = $dbh->prepare("SELECT subject FROM livepoll_item WHERE livepoll_item_id = $item_id");
	$sth->execute();
	($subject) = $sth->fetchrow_array or die "Can't find sequence from item_id($item_id), info_id($info_id)";

	#
	# SELECT
	#
	$sth = $dbh->prepare("SELECT livepoll_item_select_id, sequence, subject, count FROM livepoll_item_select WHERE item_id=$item_id ORDER BY sequence");
	$sth->execute();
	while ( my ($select_id, $seq, $subject, $count) = $sth->fetchrow_array ) {
		$content .= "$seq) $subject</br><span id=input_$seq><input type=button value='선택' onclick='choice(\"select\", $seq)'></span> <span id='graph_$seq' style='background-color: red; padding-right: ${count}0'>&nbsp;</span> <span id=count_$seq>$count</span></p>";
	}

	#
	# CHECK
	#
	$sth = $dbh->prepare("SELECT livepoll_item_check_id, sequence, subject, count FROM livepoll_item_check WHERE item_id=$item_id ORDER BY sequence");
	$sth->execute();
	while ( my ($check_id, $seq, $subject, $count) = $sth->fetchrow_array ) {
		$content .= "$seq) $subject</br><span id=input_$seq><input id=input_$seq type=button value='선택' onclick='choice(\"check\", $seq)'></span> <span id='graph_$seq' style='background-color: red; padding-right: ${count}0'>&nbsp;</span> <span id=count_$seq>$count</span></p>";
	}

	#
	# COMMENT
	#
	if ( $allowcomment ) {
		$content .= "기타) <input type=text id=msg></p><span id='comment'></span><br>";
		#$sth = $dbh->prepare("SELECT livepoll_comment_id, comment FROM livepoll_item_comment WHERE item_id=$item_id");
		#$sth->execute();
		#while ( my ($comment_id, $comment) = $sth->fetchrow_array ) {
		#	#$content .= "기타) <input type=text id=msg></p><span id='comment'></span><br>";
		#}
	}

	$content .= '<p>';

	$c->render('respondent', header => header(), footer => footer(), subject => $subject, content => $content, info_id => $info_id, item_id => $item_id, item_id_prev => $item_id_prev, item_id_next => $item_id_next, sequence => $sequence);
	closer();
};

#
# 메인스크린 영역
#
get '/livepoll/screen' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id") || die "need a info_id";
	my $item_id = $c->param("item_id");

	# item_id가 없으면 진행 상태 정보 가져오기
	unless ( $item_id ) {
		my $sth = $dbh->prepare("SELECT item_id FROM livepoll_state WHERE info_id=$info_id");
		$sth->execute();
		($item_id) = $sth->fetchrow_array;

		$item_id = 1 if not $item_id;
	}

	my $content = "";
	# 필요한 정보
	# prev item_id
	# next item_id
	# item subject
	# 	select subject, count
	# 	check subject, count
	# comment
	my $sth;
	my $sequence;
	my $subject;
	my $allowcomment;
	my $item_id_prev;
	my $item_id_next;
	my $item_subject;
	my $tmp;

	$sth = $dbh->prepare("SELECT allowcomment, sequence FROM livepoll_item WHERE livepoll_item_id = $item_id");
	$sth->execute();
	($allowcomment, $sequence) = $sth->fetchrow_array or die "Can't find sequence from item_id($item_id), info_id($info_id)";

	$sth = $dbh->prepare("SELECT livepoll_item_id, MAX(sequence) FROM livepoll_item WHERE sequence < $sequence AND info_id=$info_id");
	$sth->execute();
	($item_id_prev) = $sth->fetchrow_array;
	$item_id_prev = $item_id unless $item_id_prev;

	$sth = $dbh->prepare("SELECT livepoll_item_id, MIN(sequence) FROM livepoll_item WHERE sequence > $sequence AND info_id=$info_id");
	$sth->execute();
	($item_id_next, $tmp) = $sth->fetchrow_array;
	$item_id_next = $item_id unless $item_id_next;

	$sth = $dbh->prepare("SELECT subject FROM livepoll_item WHERE livepoll_item_id = $item_id");
	$sth->execute();
	($subject) = $sth->fetchrow_array or die "Can't find sequence from item_id($item_id), info_id($info_id)";

	#
	# SELECT
	#
	$sth = $dbh->prepare("SELECT livepoll_item_select_id, sequence, subject, count FROM livepoll_item_select WHERE item_id=$item_id ORDER BY sequence");
	$sth->execute();
	while ( my ($select_id, $seq, $subject, $count) = $sth->fetchrow_array ) {
		$content .= "$seq) $subject</br><span id='graph_$seq' style='background-color: red; padding-right: ${count}0'>&nbsp;</span> <span id=count_$seq>$count</span></p>";
	}

	#
	# CHECK
	#
	$sth = $dbh->prepare("SELECT livepoll_item_check_id, sequence, subject, count FROM livepoll_item_check WHERE item_id=$item_id ORDER BY sequence");
	$sth->execute();
	while ( my ($check_id, $seq, $subject, $count) = $sth->fetchrow_array ) {
		$content .= "$seq) $subject</br><span id='graph_$seq' style='background-color: red; padding-right: ${count}0'>&nbsp;</span> <span id=count_$seq>$count</span></p>";
	}

	#
	# COMMENT
	#
	if ( $allowcomment ) {
		$content .= "기타) <input type=text id=msg></p><span id='comment'></span><br>";
		#$sth = $dbh->prepare("SELECT livepoll_comment_id, comment FROM livepoll_item_comment WHERE item_id=$item_id");
		#$sth->execute();
		#while ( my ($comment_id, $comment) = $sth->fetchrow_array ) {
		#	#$content .= "기타) <input type=text id=msg></p><span id='comment'></span><br>";
		#}
	}

	$content .= '<p>';

	$c->render('screen', header => header(), footer => footer(), subject => $subject, content => $content, info_id => $info_id, item_id => $item_id, item_id_prev => $item_id_prev, item_id_next => $item_id_next, sequence => $sequence);
	closer();
};

get '/livepoll/save_state' => sub {
	my $c = shift;
	my $info_id = $c->param("info_id") || die "need a info_id";
	my $item_id = $c->param("item_id") || die "need a item_id";
	my $item_id_next = $c->param("item_id_next") || die "need a item_id";

	my $sth;

	if ( $response->{$info_id}->{$item_id} ) {
		#
		# SELECT
		#
		foreach my $seq ( keys %{ $response->{$info_id}->{$item_id}->{graph}->{select} } ) {
			my $count = $response->{$info_id}->{$item_id}->{graph}->{select}->{$seq};
			$dbh->do("UPDATE livepoll_item_select SET count=$count WHERE item_id=$item_id AND sequence=$seq");
		}

		#
		# CHECK
		#
		foreach my $seq ( keys %{ $response->{$info_id}->{$item_id}->{graph}->{check} } ) {
			my $count = $response->{$info_id}->{$item_id}->{graph}->{check}->{$seq};
			$dbh->do("UPDATE livepoll_item_check SET count=$count WHERE item_id=$item_id AND sequence=$seq");
		}

		#
		# COMMENT
		#
		$dbh->do("DELETE FROM livepoll_item_comment WHERE item_id=$item_id");
		foreach my $msg ( keys %{ $response->{$info_id}->{$item_id}->{comment} } ) {
			my $msg = $dbh->quote($msg);
			$dbh->do("INSERT INTO livepoll_item_comment(item_id, comment) VALUES ($item_id, $msg)");
		}
	}

	$dbh->do("DELETE FROM livepoll_state");
	$dbh->do("INSERT INTO livepoll_state (info_id, item_id) VALUES ( $info_id, $item_id_next )");

	$c->render(text => "<html> <meta http-equiv='refresh' content='0; url=/livepoll/screen?info_id=$info_id&item_id=$item_id_next'></meta> </html>");
};

app->start;




sub closer {
	$counter++;
}

sub header {
	return <<"HEADER";
<html>
<body>
HEADER
}

sub footer {
	return <<"FOOTER";
</body>
</html>
FOOTER
}

__DATA__

@@ admin.html.ep
<%= $title %>

@@ counter.html.ep
<%= $title %>

@@ admin.poll.list.html.ep
<%== $header %>
<h1><%= $title %></h1>
<a href=/livepoll/admin/poll/add>추가하기</a><p>
<%== $content %>
<%== $footer %>

@@ admin.poll.add.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/poll/add>
설문주제: <input type=text name=desc size=60> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.poll.edit.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/poll/edit>
설문주제: <input type=text name=desc value='<%= $desc %>'size=60> <input type=submit value=SUBMIT>
<input type=hidden name=info_id value=<%= $info_id %>>
</form>
<%== $footer %>

@@ admin.poll.rm.html.ep
<%== $header %>
<h1><%= $title %></h1>
정말 삭제하시겠습니까? <a href=/livepoll/admin/poll/rm?info_id=<%= $info_id %>&check=1>YES</a>, <a href=/livepoll/admin/poll/list>NO</a>
<%== $footer %>

@@ admin.poll.view.html.ep
<%== $header %>
<h1><%= $title %></h1>
<a href=/livepoll/admin/poll/list>상위페이지</a>, 
<a href=/livepoll/admin/item/add?info_id=<%= $info_id %>>추가하기</a><p>
<%== $content %>
<%== $footer %>

@@ admin.item.add.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/item/add>
<input type=hidden name=info_id value=<%= $info_id %>>
설문문항: <input type=text name=subject size=60> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.item.edit.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/item/edit>
<input type=hidden name=info_id value=<%= $info_id %>>
<input type=hidden name=item_id value=<%= $item_id %>>
설문주제: <input type=text name=subject value='<%= $subject %>'size=60> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.item.add.select.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/item/add/select>
<input type=hidden name=info_id value=<%= $info_id %>>
<input type=hidden name=item_id value=<%= $item_id %>>
선택항목: <input type=text name=subject size=60> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.item.edit.select.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/item/edit/select>
<input type=hidden name=info_id value=<%= $info_id %>>
<input type=hidden name=item_id value=<%= $item_id %>>
<input type=hidden name=select_id value=<%= $select_id %>>
선택항목: <input type=text name=subject size=60 value='<%= $subject %>'> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.item.edit.check.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/item/edit/check>
<input type=hidden name=info_id value=<%= $info_id %>>
<input type=hidden name=item_id value=<%= $item_id %>>
<input type=hidden name=check_id value=<%= $check_id %>>
다중선택항목: <input type=text name=subject size=60 value='<%= $subject %>'> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.item.add.check.html.ep
<%== $header %>
<h1><%= $title %></h1>
<form action=/livepoll/admin/item/add/check>
<input type=hidden name=info_id value=<%= $info_id %>>
<input type=hidden name=item_id value=<%= $item_id %>>
다중선택항목: <input type=text name=subject size=60> <input type=submit value=SUBMIT>
</form>
<%== $footer %>

@@ admin.item.add.comment.html.ep
<%== $header %>
<h1><%= $title %></h1>
기타항목을 활성화 하시겠습니까? <a href=/livepoll/admin/item/add/comment?info_id=<%= $info_id %>&item_id=<%= $item_id %>&check=1>YES</a>, <a href=/livepoll/admin/poll/view?info_id=<%= $info_id %>>NO</a>
<%== $footer %>

@@ admin.item.rm.check.html.ep
<%== $header %>
<h1><%= $title %></h1>
정말 삭제하시겠습니까? <a href=/livepoll/admin/item/rm/check?info_id=<%= $info_id %>&check=1&check_id=<%= $check_id %>>YES</a>, <a href=/livepoll/admin/poll/view?info_id=<%= $info_id %>>NO</a>
<%== $footer %>

@@ admin.item.reset.check.html.ep
<%== $header %>
<h1><%= $title %></h1>
정말 초기화 하시겠습니까? <a href=/livepoll/admin/item/reset/check?info_id=<%= $info_id %>&check=1&check_id=<%= $check_id %>>YES</a>, <a href=/livepoll/admin/poll/view?info_id=<%= $info_id %>>NO</a>
<%== $footer %>

@@ admin.item.rm.select.html.ep
<%== $header %>
<h1><%= $title %></h1>
정말 삭제하시겠습니까? <a href=/livepoll/admin/item/rm/select?info_id=<%= $info_id %>&check=1&select_id=<%= $select_id %>>YES</a>, <a href=/livepoll/admin/poll/view?info_id=<%= $info_id %>>NO</a>
<%== $footer %>

@@ admin.item.reset.select.html.ep
<%== $header %>
<h1><%= $title %></h1>
정말 초기화 하시겠습니까? <a href=/livepoll/admin/item/reset/select?info_id=<%= $info_id %>&check=1&select_id=<%= $select_id %>>YES</a>, <a href=/livepoll/admin/poll/view?info_id=<%= $info_id %>>NO</a>
<%== $footer %>

@@ admin.item.rm.html.ep
<%== $header %>
<h1><%= $title %></h1>
정말 삭제하시겠습니까? <a href=/livepoll/admin/item/rm?info_id=<%= $info_id %>&check=1&item_id=<%= $item_id %>>YES</a>, <a href=/livepoll/admin/poll/view?info_id=<%= $info_id %>>NO</a>
<%== $footer %>

@@ synctest.html.ep
<%== $header %>
<script src="//ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min.js"></script>
<h1><%= $title %></h1>

<script type="text/javascript">
$(function () {
	var ws = new WebSocket('ws://203.252.219.164:3000/livepoll/websocket/synctest');

	ws.onopen = function () {
		document.getElementById("status").innerHTML = "Connection Opened!";
		ws.send($('#msg').val());
	};

	ws.onmessage = function (msg) {
		var res = JSON.parse(msg.data);

		document.getElementById("result").innerHTML = "";
		document.getElementById("status").innerHTML = "Connection Opened! Clients: " + res["total"];

		var i = 0;
		for ( var id in res["msg"] ) {
			$('#result').append('<div>' + i + ': ' + res["msg"][id] + '</div>');
			i++;
		}
	};

	$('#msg').keydown(function (e) {
		if ( $('#msg').val() ) {
			ws.send($('#msg').val());
			if (e.keyCode == 13) {
				$('#msg').val('');
			}
		}
	});
});
</script>

<div id=status>Can't connect websocket!</div></p>
<input type="text" id="msg" /> <small>글을 쓰고 엔터를 누르세요</small></p>
<div id=result></div>

<%== $footer %>

@@ respondent.html.ep
<%== $header %>
<span id=status>Can't connect websocket!</span>
<script src="//ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min.js"></script>
<script type="text/javascript">

	var ws = new WebSocket('ws://203.252.219.164:3000/livepoll/websocket/respondent?info_id=<%= $info_id %>&item_id=<%= $item_id %>');

$(function () {
	ws.onopen = function () {
		document.getElementById("status").innerHTML = "Connected Websocket!";
		ws.send("");
	};

	ws.onmessage = function (msg) {
		var res = JSON.parse(msg.data);

		document.getElementById("status").innerHTML = "접속자 수: " + res["total"];

		// graph
		if ( res["graph"]["select"] ) {
			for ( var id in res["graph"]["select"] ) {
				var graphid = "graph_" + id;
				var countid = "count_" + id;
				document.getElementById(graphid).style.paddingRight = res["graph"]["select"][id] * 10;
				document.getElementById(countid).innerHTML = res["graph"]["select"][id];
			}
		} else {
			for ( var id in res["graph"]["check"] ) {
				var graphid = "graph_" + id;
				var countid = "count_" + id;
				document.getElementById(graphid).style.paddingRight = res["graph"]["check"][id] * 10;
				document.getElementById(countid).innerHTML = res["graph"]["check"][id];
			}

		}

		// comment
		$('#comment').html('');
		for ( var message in res["comment"] ) {
			$('#comment').append('<div>- ' + message + '</div>');
		}

	};

	$('#msg').keydown(function (e) {
		if ( $('#msg').val() ) {
			if (e.keyCode == 13) {
				ws.send($('#msg').val());
				$('#msg').val('');
			}
		}
	});

});

	function choice(type, graphid) {
		var i;
		for ( i = 0; i < 50; i++ ) {
			if ( i == graphid ) {
				var spanid = "#" + "input_" + graphid;
				$(spanid).html("<input type=button value='취소' onclick='cancel(" + '"' + type + '", ' + graphid+")'>");
			} else {
				var spanid = "#" + "input_" + i;
				if ( $(spanid) ) { 
					$(spanid).html("<input type=button value='취소' onclick='cancel(" + '"' + type + '", ' + graphid+")'>");
				}
			}
		}

		ws.send("+" + graphid + "_" + type);
	}


	function cancel(type, graphid) {
		var i;
		for ( i = 0; i < 50; i++ ) {
			if ( i == graphid ) {
				var spanid = "#" + "input_" + graphid;
				$(spanid).html("<input type=button value='선택' onclick='choice(" + '"' + type + '", ' + graphid+")'>");
			} else {
				var spanid = "#" + "input_" + i;
				if ( $(spanid) ) { 
					$(spanid).html("<input type=button value='선택' onclick='choice(" + '"' + type + '", ' + i +")'>");
				}
			}
		}

		ws.send("-" + graphid + "_" + type);
	}

</script>
<h1><%= $subject %></h1>
<%== $content %>

<script type="text/javascript">
</script>

<%== $footer %>

@@ screen.html.ep
<%== $header %>
<a href=/livepoll/save_state?info_id=<%= $info_id %>&item_id=<%= $item_id %>&item_id_next=<%= $item_id_prev %>>prev</a>, 
<a href=/livepoll/save_state?info_id=<%= $info_id %>&item_id=<%= $item_id %>&item_id_next=<%= $item_id_next %>>next</a>, 
 <span id=status>Can't connect websocket!</span>
<script src="//ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min.js"></script>
<script type="text/javascript">

	var ws = new WebSocket('ws://203.252.219.164:3000/livepoll/websocket/respondent?info_id=<%= $info_id %>&item_id=<%= $item_id %>');

$(function () {
	ws.onopen = function () {
		document.getElementById("status").innerHTML = "Connected Websocket!";
		ws.send("");
	};

	ws.onmessage = function (msg) {
		var res = JSON.parse(msg.data);

		document.getElementById("status").innerHTML = "접속자 수: " + res["total"];

		// graph
		if ( res["graph"]["select"] ) {
			for ( var id in res["graph"]["select"] ) {
				var graphid = "graph_" + id;
				var countid = "count_" + id;
				document.getElementById(graphid).style.paddingRight = res["graph"]["select"][id] * 10;
				document.getElementById(countid).innerHTML = res["graph"]["select"][id];
			}
		} else {
			for ( var id in res["graph"]["check"] ) {
				var graphid = "graph_" + id;
				var countid = "count_" + id;
				document.getElementById(graphid).style.paddingRight = res["graph"]["check"][id] * 10;
				document.getElementById(countid).innerHTML = res["graph"]["check"][id];
			}

		}

		// comment
		$('#comment').html('');
		for ( var message in res["comment"] ) {
			$('#comment').append('<div>- ' + message + '</div>');
		}

	};

	$('#msg').keydown(function (e) {
		if ( $('#msg').val() ) {
			if (e.keyCode == 13) {
				ws.send($('#msg').val());
				$('#msg').val('');
			}
		}
	});

});

</script>
<h1><%= $subject %></h1>
<%== $content %>

<script type="text/javascript">
</script>

<%== $footer %>


