#!/usr/bin/perl -w

use strict;
use Time::Local;


sub sqltime {
	my $time = shift;
	$time = time()
		if !defined $time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
	$mon++;
	$year += 1900;
	$mday = "0".int($mday) if $mday < 10;
	$mon =  "0".int($mon)  if $mon < 10;
	$hour = "0".int($hour) if $hour < 10;
	$min =  "0".int($min)  if $min < 10;
	$sec =  "0".int($sec)  if $sec < 10;
	return "$year-$mon-$mday $hour:$min:$sec";
}


sub sqldate {
	my $time = shift;
	$time = time()
		if !defined $time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
	$mon++;
	$year += 1900;
	$mday = "0".int($mday) if $mday < 10;
	$mon =  "0".int($mon)  if $mon < 10;
	return "$year-$mon-$mday";
}


sub timesql {
	my $sqltime = shift;
	return undef
		if !defined $sqltime || $sqltime !~ /(\d\d+)-(\d+)-(\d+)/;
	my $year = $1;
	my $mon = $2;
	my $mday = $3;
	my $rest = $';
	my $hour = "0";
	my $min = "0";
	my $sec = "0";
	my $diff = 0;
	if ( $rest =~ /(\d+):(\d+):(\d+)/ ) {
		$rest = $';
		$hour = $1;
		$min = $2;
		$sec = $3;
		if ( $rest =~ /\+(\d\d?)/ ) {
			$diff -= $1 * 3600;
		}
		if ( $rest =~ /\-(\d\d?)/ ) {
			$diff += $1 * 3600;
		}
	}
	$mon--;
	$year -= 1900;
	my $value = eval{ timegm($sec, $min, $hour, $mday, $mon, $year) };
	if (!defined $value) {
		if ( ($mon == 1) && ($mday == 29) ) {
			$value = eval{ timegm($sec, $min, $hour, 1, 2, $year) };
		}
	}
	$value += $diff;
	return $value;
}


sub mailtime {
	my $time = shift;
	my @wdays = qw(Sun Mon Tue Wed Thu Fri Sat);
	my @mons = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	$time = time()
		if !defined $time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
	$mon = $mons[$mon];
	$wday = $wdays[$wday];
	$year += 1900;
	$mday = int($mday);
	$hour = "0".int($hour)
		if $hour < 10;
	$min =  "0".int($min)
		if $min < 10;
	$sec =  "0".int($sec)
		if $sec < 10;
	return "$wday, $mday $mon $year $hour:$min:$sec -0000";
}

sub timemail {
	my $mailtime = shift;
	my %mons = (
		'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6,
		'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12
	);
	my $monp = join "|", (keys %mons);
	return undef
		if !defined $mailtime || $mailtime !~ /(\d+) ($monp) (\d+) (\d+):(\d+):(\d+)/i;
	my $mday = $1;
	my $mon = $mons{lc $2};
	my $year = $3;
	my $hour = $4;
	my $min = $5;
	my $sec = $6;
	my $rest = $';
	my $diff = 0;
	$diff = int($1)
		if $rest =~ /([\+\-]\d+)/;
	my $time = timegm($sec, $min, $hour, $mday, $mon-1, $year-1900);
	$time -= ($diff*36);
	return $time;
}



sub min_sqltime {
	my $date = shift;
	return undef
		if !defined $date;
	return $date
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)?$/;
	return "$1-$2-$3 $4:$5:00"
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)$/;
	return "$1-$2-$3 $4:00:00"
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)$/;
	return "$1-$2-$3 00:00:00"
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/;
	return "$1-$2-01 00:00:00"
		if $date =~ /^(\d\d\d\d)-(\d\d)$/;
	return "$1-01-01 00:00:00"
		if $date =~ /^(\d\d\d\d)$/;
	return undef;
}

sub max_sqltime_days_in_month {
	my $year = int(shift);
	my $month = int(shift);
	return "00"
		if $month > 12;
	return "00"
		if $month < 1;
	my @days_per_month = qw(31 28 31 30 31 30 31 31 30 31 30 31);
	my $days = $days_per_month[$month-1];
	if ( $month == 2 ) {
		if ( (($year % 400) == 0) || ((($year % 100) != 0) && (($year % 4) == 0)) ) {
			$days++;
		}
	}
	return $days;
}

sub max_sqltime {
	my $date = shift;
	return $date
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d)?$/;
	return "$1-$2-$3 $4:$5:59"
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)$/;
	return "$1-$2-$3 $4:59:59"
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)$/;
	return "$1-$2-$3 23:59:59"
		if $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/;
	return "$1-$2-".max_sqltime_days_in_month($1,$2)." 23:59:59"
		if $date =~ /^(\d\d\d\d)-(\d\d)$/;
	return "$1-12-31 23:59:59"
		if $date =~ /^(\d\d\d\d)$/;
	return undef;
}

sub check_sqltime {
	my $date = min_sqltime(shift);
	return undef
		if !defined $date;
	return undef
		if $date !~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d)?$/;
	my $year = $1;
	my $month = $2;
	my $day = $3;
	my $hour = $4;
	my $minute = $5;
	my $second = $6;
	
	return 0 if $month < 1;
	return 0 if $month > 12;

	return 0 if $day < 1;
	return 0 if $day > max_sqltime_days_in_month($year, $month);

	return 0 if $hour > 23;
	return 0 if $minute > 59;
	return 0 if $second > 59;
	
	return 1;
}



sub parse_period {
	my $time = shift;
	return undef
		if !defined $time;
	$time =~ s/ //og;
	return 0
		if !length($time);
	return $time
		if $time =~ /^\-[0-9]+$/;

	my $neg = 0;
	$neg = 1 if ( $time =~ s/^-// );

	my $s = 0;
	my $m = 0;
	my $h = 0;
	my $d = 0;
	my $w = 0;
	my $M = 0;
	my $Y = 0;
	while ( $time =~ s/([0-9]+)(s|$)// ) { $s += $1; }
	while ( $time =~ s/([0-9]+)m// ) { $m += $1; }
	while ( $time =~ s/([0-9]+)h// ) { $h += $1; }
	while ( $time =~ s/([0-9]+)d// ) { $d += $1; }
	while ( $time =~ s/([0-9]+)w// ) { $w += $1; }
	while ( $time =~ s/([0-9]+)M// ) { $M += $1; }
	while ( $time =~ s/([0-9]+)Y// ) { $Y += $1; }

	$d += $Y * 365;
	$s += $M * (732) * 3600;

	$d += $w * 7;
	$h += $d * 24;
	$m += $h * 60;
	$s += $m * 60;

	return (-$s)
		if $neg;
	return $s;
}


sub renew_expdate {
	my $old_expdate = shift;
	my $period = shift;
	return undef
		if !defined $old_expdate;
	return undef
		if !defined $period;
	$period =~ s/ //og;
	return undef
		if !length($period);

	print STDERR "renew_expdate($old_expdate)\n";

	if (!($old_expdate =~ /^([0-9]{4})\-([0-9]{1,2})\-([0-9]{1,2})(.*)$/)) {
		return undef;
	}
	my $expdate_y = $1;
	my $expdate_m = $2;
	my $expdate_d = $3;
	my $expdate_r = $4;

	my $Y = 0;
	while ( $period =~ s/([0-9]+)Y// ) { $Y += $1; }

	my $M = 0;
	while ( $period =~ s/([0-9]+)M// ) { $M += $1; }

	my $D = 0;
	while ( $period =~ s/([0-9]+)d// ) { $D += $1; }

	my $renew_expdate_y = ($expdate_y + $Y);
	my $renew_expdate_m = ($expdate_m + $M);
	if ($renew_expdate_m > 12) {
		$renew_expdate_y++;
		$renew_expdate_m -= 12;
	}
	my $renew_expdate_d = ($expdate_d + $D);

	my $new_expdate = sprintf("%04d", ($renew_expdate_y)) . "-" . sprintf("%02d", ($renew_expdate_m)) . "-" . sprintf("%02d", ($renew_expdate_d)) . $expdate_r;

	print STDERR " -> $new_expdate\n";
	return $new_expdate;
}


sub anniversary_to_expdate {
	my $anniversary = shift; # 0000-MM-DD # the first four digits/characters have to be also provided to prevent
								# formatting mistakes, but will be ignored
	my $celebrate = shift || "BegDay";	# BegDay|EndDay, maybe if needed also BegMon|EndMon
										# BegDay ==> Beginning of the Day means, if anniversary is 0000-10-30
										# and current date is 2008-10-30, then the result would be 2009-10-30

	return undef
		if $anniversary !~  /^....\-\d\d\-\d\d/;

	my $now = sqltime();

	if ( $celebrate eq "BegDay" ) {
		return substr($now,0,5) .  substr($anniversary,5,5)
			if substr($now,5,5) lt substr($anniversary,5,5);
		return substr($now,0,4) + 1 . "-" . substr($anniversary,5,5);
	}
	elsif ( $celebrate eq "EndDay" ) {
		return substr($now,0,5) .  substr($anniversary,5,5)
			if substr($now,5,5) le substr($anniversary,5,5);
		return substr($now,0,4) + 1 . "-" . substr($anniversary,5,5);
	}
	else {
		return undef;
	}

}


1;

