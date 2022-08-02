#!/usr/bin/perl -w

#use strict; # LEADS TO SESSION BROKEN!!!

use Socket qw(IPPROTO_TCP TCP_NODELAY);

use IO::Socket;
use IO::Socket::INET;
use IO::Socket::UNIX;

use utf8;

my $udpSocket = undef;
my $udpTimeout = 0.5;
my $udpId = 0;


sub ptf_select {
	my $vec1 = shift;
	my $vec2 = shift;
	my $vec3 = shift;
	my $timeout = shift;
	
	my ($nfound,$timeleft) = select($vec1, $vec2, $vec3, ${$timeout});
	${$timeout} = $timeleft;
	return $nfound;
}

sub ptf_splitValueBlock {
	my %data;
	my $b = shift;
	while ( $b =~ /(?:\n|^)([\w\d\[\]\-]+)[ ]*\=[ ]*([^\n]*)/ ) {
		$b = $';
		my $id = uc($1);
		my $val = $2;
		chomp $val;
		$id =~ s/(\s|_)//og;
		$data{$id} = $val if ( defined $val );
	}
	return %data;
}

sub ptf_openUDPSocket {

	if ( $udpSocket ) {
		close $udpSocket;
		undef $udpSocket;
	}
	$udpSocket = new IO::Handle;
	
	my $proto = getprotobyname('udp');
	my $paddr = sockaddr_in(0, INADDR_ANY); # 0 means let kernel pick

	socket($udpSocket, PF_INET, SOCK_DGRAM, $proto)   || die "socket: $!";
	bind($udpSocket, $paddr)						  || die "bind: $!";
}


ptf_openUDPSocket();


sub ptf_stdSockets {
	my @sockets = @_;
	my @newsockets = ();
	
	foreach my $socket ( @sockets ) {
		my $newsocket = "";
	
		foreach my $line ( split /\n/, $socket ) {
			$line =~ s/\n//;
			if ( $line =~ /^mregd:\/\//i ) {
				$newsocket .= "$line\n";
			}
			elsif ( $line =~ /^mregd\+udp:\/\//i ) {
				$newsocket .= "$line\n";
			}
			elsif ( $line =~ /^xservice:\/\//i ) {
			$newsocket .= "$line\n";
			}
			elsif ( $line !~ /\/\// ) {
				$newsocket .= "mregd://$line\n";
			}
		}
		push @newsockets, $newsocket;
#		print STDERR "$newsocket";
	}
	
	return @newsockets;
}



sub ptf_getPreferredSockets {
	my @sockets = ptf_stdSockets(@_);
	my @preferred_sockets = ();

	$udpId++;
	my $packets = 0;
	
	my $i;
	
	my @tests = ();
	
	for ( $i = 0; $i <= $#sockets; $i++ ) {
		my $ptf = $sockets[$i];
		my @lines = split /\n/, $ptf;
		my @test = ();
	
		foreach my $line ( @lines ) {
			if ( $line =~ /^xservice:\/\/([^\s]+)/i ) {
				my $service = $1;
				my $cache = new IO::Socket::UNIX("/tmp/ServiceCache");
				syswrite $cache, "LOCATE SERVICE $service\n";
				my $cr = <$cache>;
				if ( $cr =~ /^OK ([^\n]+)/ ) {
					my $address = $1;
					foreach my $url ( split / /, $address ) {
						if ( $url =~ /^mregd\+udp:\/\/([^\@]+)\@([^:]+):([0-9]+)/i ) {
							push @test, $url;
							$packets++;
						}
					}
				}
			}
			if ( $line =~ /^mregd\+udp:\/\/([^\@]+)\@([^:]+):([0-9]+)/i ) {
				push @test, $line;
				$packets++;
			}
		}

		$tests[$i] = \@test;

		if ( !@test ) {
			$preferred_sockets[$i] = $ptf;
		}
	}

	my $rout;
	my $rin = '';
	vec($rin, fileno($udpSocket), 1) = 1;

	my %socketValue = ();

	foreach my $timeout ( 0.005, 0.025, 0.070, 0.150, 0.250, 1 ) {
		if ( $packets && ( ($timeout == 0.005) || ($timeout == 0.250) ) ) {
			for ( $i = 0; $i <= $#sockets; $i++ ) {
				next if defined $preferred_sockets[$i];

				my @test = @{$tests[$i]};

				my $j;
				for ( $j = 0; $j <= $#test; $j++ ) {
					my $id = "$udpId-$i-$j";
					my $socket = $test[$j];

					if ( $socket =~ /^mregd\+udp:\/\/([^\@]+)\@([^:]+):([0-9]+)/i ) {
						my $auth = $1;
						my $host = $2;
						my $port = $3;
						$auth =~ s/~/:/;
						my $request = "PTF1.0/request/status\nauth=$auth\nid=$id\n";
						my $hisiaddr = inet_aton($host) || next;
						my $hispaddr = sockaddr_in($port, $hisiaddr) || next;
						send($udpSocket, $request, 0, $hispaddr) || next;
					}
				}
			}
		}

		my $t = $timeout;
		while ($packets && ptf_select($rout = $rin, undef, undef, \$t)) {
			my $data;

			($hispaddr = recv($udpSocket, $data, 1024, 0))		|| die "recv: $!";
	
			if ( $data =~ /^PTF1\.[0-9]+\/response\/status\n/ ) {
				my $payload = $';
				my %data = ptf_splitValueBlock($payload);
				my $id = $data{'ID'};
				my ( $udpId2, $i2, $j2 ) = split /-/, $id;

				next
					if !($udpId2 == $udpId);
				next
					if ( $i2 < 0 );
				next
					if ( $i2 > $#sockets );
				next
					if ( $j2 < 0 );
				next
					if ( $j2 > $#{$tests[$i2]} );
		
				my $socket = $data{'SOCKET'};
				my $clients = $data{'CLIENTS'};
				my $sessionsonline = $data{'SESSIONSONLINE'};
				my $maxsessions = $data{'MAXSESSIONS'};

				$socket = $tests[$i2][$j2];

#				print STDERR "$socket replied: ".($timeout)."\n";
#				print STDERR "CL: $clients MAX: $maxsessions ONLINE: $sessionsonline\n";

				$packets-- if !exists $socketValue{$socket};

				my $rating = 128 - $clients;
				if ( $sessionsonline > 0 ) {
					$rating += 128 if $maxsessions - $clients > 0;
				}
				$rating += int(rand($sessionsonline-$clients)) if $sessionsonline-$clients > 0;
		
				$socketValue{$socket} = $rating;
		
				if ( defined $preferred_sockets[$i2] ) {
					if ( $socketValue{$preferred_sockets[$i2]} < $rating ) {
						$preferred_sockets[$i2] = $socket;
					}
				}
				else {
					$preferred_sockets[$i2] = $socket;
				}
			}
		}

		if ( $packets ) {
			my $sockets_ready = 0;
			for ( $i = 0; $i <= $#sockets; $i++ ) {
				if ( defined $preferred_sockets[$i] ) {
					$sockets_ready++
						if ($socketValue{$preferred_sockets[$i]} > 128) || ($timeout >= 0.070);
#					print STDERR "Socket: $preferred_sockets[$i]: ".$socketValue{$preferred_sockets[$i]}."\n";
				}
			}
			$packets = 0 if $sockets_ready > $#sockets;
		}
	}

	for ( $i = 0; $i <= $#sockets; $i++ ) {
		if ( !defined $preferred_sockets[$i] ) {
			$preferred_sockets[$i] = "";
		}
	}

	return @preferred_sockets;
}



sub ptf_createRequest {
	my $command = shift;
	my $config = shift || {};
	
	return $command
		if !ref $command;

	my $request = "";

	if ( defined $config ) {
		my $user = $config->{'user'};
		my $nolog  = $config->{'nolog'};
		my $maxruntime  = $config->{'maxruntime'};
		$request .= "[RRPPROXY]\n"
				   ."version=1\n"
				   .(($user)? "user=$user\n" : "")
				   .(($nolog)?  "nolog=$nolog\n"   : "")
				   .(($maxruntime)?  "maxruntime=$maxruntime\n"   : "")
				   ."\n";
	}

	$request .= "[COMMAND]\n";

	my $id;
	foreach $id ( keys( %$command ) ) {
		next if $id =~ /^X\-(WHOIS|WDRP)\-/i;
		if ( defined $command->{$id} ) {
			if ( ref $command->{$id} ) {
				my $list = $command->{$id};
				my $ix = 0;
				foreach ( @$list ) {
					$_ = "" if ! defined $_;
					my $line = $id."$ix=$_\n";
					utf8::encode($line) if utf8::is_utf8($line);
					$request .= $line;
					$ix++;
				}
			}
			else {
				my $line .= "$id=".$command->{$id}."\n";
				utf8::encode($line) if utf8::is_utf8($line);
				$request .= $line;
			}
		}
	}

	return $request;
}



sub ptf_sendRequests {
	my @requests = @_;

	my @sockets = ();

	foreach my $rinfo ( @requests ) {
		my ($command,$config) = @{$rinfo};
		my $ptf = $config->{'ptf'};
		push @sockets, $ptf;
	}
	
	@sockets = ptf_getPreferredSockets(@sockets);

	my @handles = ();

	$udpId++;
	
	my $i;
	for ( $i = 0; $i <= $#requests; $i++ ) {
		my $rinfo = $requests[$i];
		my ($command,$config) = @{$rinfo};

		my $request = ptf_createRequest($command,$config);
	
		delete $config->{'udp'} if length($request) > 256;

		my $udp = $config->{'udp'};
		my $socket = $sockets[$i];
	
		if ( $udp && ($socket =~ /^mregd\+udp:\/\//i) ) {
			push @handles, ptf_sendRequestUDP($request, $socket, "$udpId-$i");
		}
		elsif ( ($socket =~ /^mregd/i) ) {
			push @handles, ptf_sendRequestStream($request, $socket);
		}
		else {
			push @handles, undef;
		}
	}
	
	return @handles;
}



sub ptf_receiveResponsesRaw {
	my @handles = @_;
	
	my $udp = 0;
	my $stream = 0;
	
	my @responses = ();
	
	foreach my $handle ( @handles ) {
		if ( !defined $handle ) {
		}
		elsif ( $handle->{'type'} eq 'UDP' ) {
			$udp++;
		}
		else {
			$stream++;
		}
		push @responses, undef;
	}
	
	if ( $udp ) {
		my $timeout = 10;
		my $rout;
		my $rin = '';
		vec($rin, fileno($udpSocket), 1) = 1;
	
		while ($udp && ptf_select($rout = $rin, undef, undef, \$timeout)) {

			my $data;

			(my $hispaddr = recv($udpSocket, $data, 1024, 0)) || die "recv: $!";
#			print STDERR "$data";

			if ( $data =~ /^PTF1\.[0-9]+\/response\/command\n/ ) {
				my $payload = $';
				my $response = "";
				if ( $payload =~ /\n(\[)/ ) {
					$payload = $`;
					$response = $1.$';
				}
				my %data = ptf_splitValueBlock($payload);
				my $id = $data{'ID'};
				my ( $udpId2, $i2 ) = split /-/, $id;

				next if !($udpId2 == $udpId);
				next if ( $i2 < 0 );
				next if ( $i2 > $#handles );

				$responses[$i2] = $response;

				$udp--;
			}
		}
	} # end if ( $udp )

	if ( $stream ) {
		my $i;
		for ( $i = 0; $i <= $#handles; $i++ ) {
			my $handle = $handles[$i];
			if ( !defined $handle ) {
			}
			elsif ( $handle->{'type'} eq 'STREAM' ) {
				my $socket = $handle->{'socket'};
				
				my $response = "";
				if ( defined $socket ) {
					my $buf;
					do {
					   my $r = sysread $socket, $buf, 65536;
					   $buf = "" if !defined $r;
					   if ( (defined $r) && ($r <= 0) ) {
						   $buf = undef;
					   }
					   $response .= $buf if defined $buf;
					   if ( $response =~ /\nEOF($|\n)/ ) {
						   $response =~ s/^login:(password:)?//;
						   $responses[$i] = $response;
						   undef $buf;
					   }
					} while ( defined $buf );
					$socket->close();
				}
			}
		}
	} # end if ( $stream )
	
	return @responses;
}



sub ptf_receiveResponses {
	my @responses = ptf_receiveResponsesRaw(@_);
	my $i;
	for ( $i = 0; $i <= $#responses; $i++ ) {
		$responses[$i] = ptf_parseResponse($responses[$i]);
	}
	return @responses;
}


sub ptf_sendRequestUDP {
	my $request = shift;
	my $socket = shift;
	my $id = shift;
	my $handle = undef;
	
	if ( $socket =~ /^mregd\+udp:\/\/([^\@]+)\@([^:]+):([0-9]+)/i ) {
		my $auth = $1;
		my $host = $2;
		my $port = $3;
		$auth =~ s/~/:/;
		my $request = "PTF1.0/request/command\nauth=$auth\nid=$id\n$request";
		print STDERR "REQUEST @ $socket\n";
		my $hisiaddr = inet_aton($host) || return undef;
		my $hispaddr = sockaddr_in($port, $hisiaddr) || return undef;
		send($udpSocket, $request, 0, $hispaddr) || return undef;

		$handle = {};
		$handle->{'type'} = 'UDP';
		$handle->{'id'} = $id;
	}
	
	return $handle;
}


my %ptf_serviceSockets = ();


sub ptf_openStreamSocketIntern {
	my $ptf = shift;
	my $socket = undef;
	
	return undef
		if $ptf !~ /^mregd(?:\+udp)?:\/\//i;
	$ptf = $';
	
	$ptf =~ /\@/ || return undef;
	my $serviceSocket = $';
	$_ = $`; /\:/ || return undef;
	my $login = $`;
	my $pass = $';
	
#	return $ptf_serviceSockets{$serviceSocket}{socket}
#		if exists $ptf_serviceSockets{$serviceSocket};

	if ( $serviceSocket =~ /^\// ) {
		my $file = $serviceSocket;
		while ( $file =~ s/\.\./\./og ) {}
		while ( $file =~ s/\/\//\//og ) {}
	
		$socket = IO::Socket::UNIX->new(Type => SOCK_STREAM,
	   									Peer => $file) || return undef;
	}
	elsif ( $serviceSocket =~ /\:?(\d+)$/ ) {
		my $port = $1;
		my $host = $` || "localhost";

		$socket = IO::Socket::INET->new(PeerAddr => $host,
										PeerPort => $port,
										Proto	=> 'tcp') || return undef;
	}
	else {
		return undef;
	}

	sysread $socket, $_, 4096;
	/login/i || return undef;
	syswrite $socket,$login."\n";
	sysread $socket, $_, 4096;
	/password/i || return undef;
	syswrite $socket,$pass."\n";

#	$ptf_serviceSockets{$serviceSocket} = { time => time(), socket => $socket };
	
	return $socket;
}


sub ptf_openStreamSocket {
	my $ptf = shift;
	$ptf =~ s/\n\r/\n/og;
	$ptf =~ s/\r\n/\n/og;
	$ptf =~ s/\r/\n/og;
	my @ptfs = split /\n/, $ptf;
	while ( defined ($ptf = shift @ptfs) ) {
		my $socket = ptf_openStreamSocketIntern($ptf);
		return $socket
			if defined $socket;
	}
	return undef;
}


sub ptf_sendRequestStream_old {
	my $request = shift;
	my $ptf = shift;
	my $handle = undef;

	my $socket = ptf_openStreamSocket($ptf);

	if ( defined $socket ) {
#		utf8::encode($request) if utf8::is_utf8($request);
		syswrite $socket, "$request\nEOF\n";
		$handle = {};
		$handle->{'type'} = 'STREAM';
		$handle->{'socket'} = $socket;
	}

	return $handle;
}


sub ptf_sendRequestStream {
	my $request = shift;
	my $ptf = shift;

	if ( $ptf !~ /^mregd(?:\+udp)?:\/\/([^\:\@]+):([^\@]+)\@([^\:]+)\:(\d+)/i ) {
		return ptf_sendRequestStream_old($request, $ptf);
	}

	return ptf_sendRequestStream_old($request, $ptf)
		if (exists $ENV{OPT_PTF}) && (!$ENV{OPT_PTF});

	my $user = $1;
	my $pass = $2;
	my $host = $3;
	my $port = $4;

	my $handle = undef;
	my $socket = IO::Socket::INET->new(
		PeerAddr => $host,
		PeerPort => $port,
		Proto	=> 'tcp',
		Blocking => 1
	);

	if ( defined $socket ) {
		setsockopt($socket, IPPROTO_TCP, TCP_NODELAY, 1);
		$socket->autoflush(1);

		syswrite $socket, "$user\n$pass\n$request\nEOF\n";
		$handle = {};
		$handle->{'type'} = 'STREAM';
		$handle->{'socket'} = $socket;
	}
	
	return $handle;
}



sub ptf_parseResponse {
	my $response = shift;
	my $lowercase = shift;
	return undef
		if !defined $response;

	my %hash;
	foreach ( split /\n/, $response ) {
		if ( /^([^\=:]*[^\t\= ])[\t ]*=[\t ]*/ ) {
			my $attr = $1;
			my $value = $';
			$attr =~ s/[\t ]*$//;
			$value =~ s/[\t ]*$//;
			if ( $attr =~ /^property\[([^\]]*)\]/i ) {
				my $prop = uc $1;
				$prop =~ s/\s//og;
				if ( exists $hash{"PROPERTY"}->{$prop} ) {
					push @{$hash{"PROPERTY"}->{$prop}}, $value;
				}
				else {
					 $hash{"PROPERTY"}->{$prop} = [$value];
					 $hash{"property"}->{lc $prop} = $hash{"PROPERTY"}->{uc $prop}
						 if $lowercase;
				}
			}
			else {
				$hash{uc $attr} = $value;
				$hash{lc $attr} = $value
					if $lowercase;
			}
		}
		elsif ( /:([^\n]*)/ ) {
			my $attr = $`;
			my $value = $1;
			if ( $attr =~ /^property\[([^\]]*)\]/i ) {
				my $prop = uc $1;
				$prop =~ s/\s//og;
				if ( exists $hash{"PROPERTY"}->{$prop} ) {
					push @{$hash{"PROPERTY"}->{$prop}}, $value;
				}
				else {
					 $hash{"PROPERTY"}->{$prop} = [$value];
					 $hash{"property"}->{lc $prop} = $hash{"PROPERTY"}->{uc $prop}
						 if $lowercase;
				}
			}
			else {
				$hash{uc $attr} = $value;
				$hash{lc $attr} = $value
					if $lowercase;
			}
		}
	}
	return \%hash;
}



sub cloneProperties {
	my $properties = shift;
	my $new = {};
	foreach my $type ( keys %{$properties} ) {
		my @list = @{$properties->{$type}};
		$new->{$type} = \@list;
	}
	return $new;
}




sub diffProperties {
	my $old_properties = shift;
	my $new_properties = shift;
	my $diff = {};

	foreach my $type ( keys %{$old_properties} ) {
		my @list = @{$old_properties->{$type}};
		if ( !exists $new_properties->{$type} ) {
			$diff->{"DEL$type"} = \@list;
		}
	}

	foreach my $type ( keys %{$new_properties} ) {
		my @list = @{$new_properties->{$type}};
		if ( !exists $old_properties->{$type} ) {
			$diff->{"ADD$type"} = \@list;
		}
		else {
			my @old_list = @{$old_properties->{$type}};
			my @add_list = ();
			my @del_list = ();
		
			my %old_check = map { $_ => 1 } @old_list;
			my %new_check = map { $_ => 1 } @list;
		
			foreach ( @old_list ) {
				push @del_list, $_ if !$new_check{$_};
			}
			foreach ( @list ) {
				push @add_list, $_ if !$old_check{$_};
			}
			$diff->{"ADD$type"} = \@add_list if @add_list;
			$diff->{"DEL$type"} = \@del_list if @del_list;
		}
	}

	return $diff;
}





sub ptf_callRaw {
	my $command = shift;
	my $config = shift || {};

	$command = ptf_createRequest($command, $config);

	my @handles = ptf_sendRequests([$command, $config]);
	my @responses = ptf_receiveResponsesRaw(@handles);
	my $response = shift @responses;
	return "[RESPONSE]\ncode=423\ndescription=error\nEOF\n"
		if !defined $response;

	return $response;
}


sub ptf_call {
	return %{ptf_parseResponse(ptf_callRaw(@_))};
}








# WRAPPER-FUNKTIONEN FUER ALTES INTERFACE


my $ptfInfo = undef;


sub initPTF {
  $ptfInfo = shift;
#  print STDERR "PTF: $ptfInfo\n";
}


my $PTF_SocketErrorString = "[RESPONSE]\ncode=423\ndescription=error\nEOF\n";

sub SendPTFCommandRaw {
	my $command = shift;
	my $config = shift || {};
	
	$command = ptf_createRequest($command, $config);
	my $newconfig = {'ptf' => $ptfInfo};
	
	my @handles = ptf_sendRequests([$command, $newconfig]);
	my @responses = ptf_receiveResponsesRaw(@handles);
	my $response = shift @responses;
	$response = $PTF_SocketErrorString
		if !defined $response;
	return $response;
}


sub SendPTFCommand {
	return %{ptf_parseResponse(SendPTFCommandRaw(@_), 1)};
}


sub sendPTFCommands {
	return finishPTFCommands(preparePTFCommands(@_));
}


sub preparePTFCommands {
	return ptf_sendRequests(@_);
}

sub finishPTFCommands {
	my @responses = ptf_receiveResponsesRaw(@_);
	my $i;
	for ( $i = 0; $i <= $#responses; $i++ ) {
		my $response = $responses[$i];
		$response = $PTF_SocketErrorString if !defined $response;
		$responses[$i] = ptf_parseResponse($response, 1);
	}
	return @responses;
}





1;
