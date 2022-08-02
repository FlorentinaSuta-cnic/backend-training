

sub createSession {

    my $server =  getEnv('SSLServerHost').":".getEnv('SSLServerPort');
    my $caFile =  getEnv('SSLCAFile');
    my $crtFile = getEnv('SSLCrtFile');
    my $keyFile = getEnv('SSLKeyFile');

    my $s = {};

    $s->{'client'} = undef;
    $s->{'command'} = '';
    $s->{'response'} = '';
    $s->{'timestamp_created'} = time;
    $s->{'timestamp_command'} = time;

    $s->{'connection_state'} = 'OFFLINE';

    $s->{'buffer_send'} = '';
    $s->{'buffer_recv'} = '';
    $s->{'handle_send'} = new IO::Handle;
    $s->{'handle_recv'} = new IO::Handle;
    $s->{'handle_error'} = new IO::Handle;

    $s->{'handle_send'}->autoflush(1);
    my $shell = "openssl s_client -connect $server";
    $shell .= " -cert $crtFile" if defined $crtFile;
    $shell .= " -key $keyFile" if defined $keyFile;
    $shell .= " -CAfile $caFile" if defined $caFile;
    $shell .= " -quiet";

    $s->{'pid'} = open3 (
      $s->{'handle_send'},
      $s->{'handle_recv'},
      $s->{'handle_error'},
      $shell
    );
    $s->{'status'} = 'NEW';

    return $s;
}

sub closeSession {
    my $s = shift;
    sendCommand_logout($s);
}


setEnv('OnlineSessions', 0);

1;
