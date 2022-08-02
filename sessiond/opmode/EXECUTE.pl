
sub createSession {

    my $shellCommand = getEnv('ShellCommand');

    my $s = {};

    $s->{'client'} = undef;
    $s->{'command'} = '';
    $s->{'response'} = '';
    $s->{'timestamp_created'} = time;
    $s->{'timestamp_command'} = time;

    $s->{'buffer_send'} = '';
    $s->{'buffer_recv'} = '';
    $s->{'handle_send'} = new IO::Handle;
    $s->{'handle_recv'} = new IO::Handle;
    $s->{'handle_error'} = new IO::Handle;

    $s->{'handle_send'}->autoflush(1);

    $s->{'pid'} = open3 (
      $s->{'handle_send'},
      $s->{'handle_recv'},
      $s->{'handle_error'},
      $shellCommand
    );

    $s->{'status'} = 'PROCESSING';
    $s->{'buffer_send'} = "EOF\n";
    $s->{'online'} = 0;

    return $s;
}

sub processSession {
    my $s = shift;
    if ( $s->{'buffer_recv'} =~ /\nEOF\n/ ) {
        processSessionResponse ($s) if $s->{'status'} eq 'PROCESSING';
    }
}

sub convertSessionCommand {
    my $s = shift;
    return $s->{'command'} . "\nEOF\n";
}

sub convertSessionResponse {
    my $s = shift;
    my $buffer = $s->{'buffer_recv'};
    $buffer =~ s/\nEOF\n//;

#    $s->{'status'} = 'PROCESSING';
#    $s->{'buffer_send'} = "EOF\n";
#    $s->{'online'} = 0;
#    setEnv("SessionsOnline", getEnv("SessionsOnline")-1);

    return $buffer;
}

sub closeSession {
    my $s = shift;
    $s->{'status'} = 'DIS';
}



1;
