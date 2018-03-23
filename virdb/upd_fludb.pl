#! /usr/bin/env perl

=head1 NAME

    upd_fludb.pl - Revise the influenza virus sequence database parsed
                   and loaded by 'load_gbvirus.pl'

=SYNOPSIS

=DESCRIPTION

    This script will revise/update these fileds:

    Table 'virus', fileds:
        'strain'
        'serotype'
        'collect_date'
        'isolate'   - if possible
        'country'   - if possible
        'host'      - if possible

    Table 'sequence', fields:
        'segment'

    Table 'feature', fields:
        'gene'

=AUTHOR

    zeroliu-at-gmail-dot-com

=VERSION

    0.0.1   - 2018-03-19

=cut

use 5.010;
use strict;
use warnings;

use DBI;
use Smart::Comments;

my $fdb = shift or die usage();

our $dbh;

die "[ERROR] Connect to SQLite3 database failed!\n" 
    unless ($dbh = conn_db($fdb));

die "[ERROR] Set database bulk mode failed!\n"
    unless ( en_db_bulk() );

my $num_upd_virus   = upd_tab_virus();

say "[OK] Total ", $num_upd_virus, " virus records updated.";

$dbh->disconnect;

#===========================================================
#
#                   Subroutines
#
#===========================================================

=pod

  Name:     usage
  Usage:    usage()
  Function: Print usage information
  Returns:  None
  Args:     None

=cut

sub usage {
    say << "EOS";
Revise the influenza virus sequence database created by script 
'load_gbvirus.pl'
Usage:
  upd_fludb.pl <db>
EOS
}

=pod

  Name:     conn_db
  Usage:    conn_db($fdb)
  Function: Connect to given SQLite3 database file
  Returns:  A database handle
  Args:     A string

=cut

sub conn_db {
    my ($fdb)   = @_;

    my $dbh;

    unless (-f $fdb) {   # Whether is a plain file
        say "[ERROR] SQLite3 file '$fdb' error!";
        return;
    }

    eval {
	    $dbh = DBI->connect(
            "dbi:SQLite:dbname=$fdb", 
	        "", "",
	        {
	            RaiseError  => 1,
	            PrintError  => 1,
	            AutoCommit  => 1,
	        }
	    ) or die $DBI::errstr, "\n";
    };

    if ($@) {
        warn "[FATAL] Connect to SQLite3 database '$fdb' failed!\n";

        return;
    }

    return $dbh;
}

=pod

  Name:     en_db_bulk
  Usage:    en_db_bulk()
  Function: Enable bulk INSERT or UPDATE operation
  Args:     None
  Returns:  None
            undef for any errors

=cut

sub en_db_bulk {
    return unless (defined $dbh);

    eval {
        $dbh->do("PRAGMA synchronous = OFF");
        $dbh->do("PRAGMA cache_size  = 100000");    # Cache siez 100M
    };
    if ($@) {
        warn "[ERROR] Setup database PRAGMA failed!\n$@\n";
        return;
    }

    return 1;
}

=pod

  Name:     upd_tab_virus
  Usage:    upd_tab_virus()
  Function: Update table 'virus'
  Args:     None
  Returns:  The number of successfully updated records

=cut

sub upd_tab_virus {
    my $sql_str = << "EOS";
SELECT 
    id,
    organism, 
    strain, 
    isolate, 
    serotype,
    country,
    collect_date
FROM
    virus
EOS
    
    my $sth;
    my $num_upd_vir = 0;

    eval {
        $sth    = $dbh->prepare($sql_str);
        $sth->execute;
    };

    if ($@) {
        warn "[ERROR] Query table 'virus' with SQL statement\n"
                , '$sql_str' , "\nfailed!\n", $@, "\n";
        return;
    }

    while (my $rh_row = $sth->fetchrow_hashref) {
        my $vir_id  = $rh_row->{'id'};
        my $org     = $rh_row->{'organism'};

        # If there was NO filed need to be updated
        # next if ( $rh_row->{'strain'} 
        #             and $rh_row->{'serotype'}
        #             and $rh_row->{'collect_date'} );

        # Debug
        say '=' x 60;
        say "Org\t===> ", $org;

        my ($cur_str, $cur_stype, $cur_date, $cur_gtype) = ('', '', '', '');

        # 'Influenza A virus (A/mallard/Iran/C364/2007(H9N2))'
        # 'Influenza B virus (B/Vienna/1/99)'
        if ($org =~ /\s(A|B|C|D)\s/) { # A|B|C|D type of flu virus
            $cur_gtype  = $1;
        }

        if ($org =~ /^Influenza.+?\((.+?)\s*\((.+?)?\)\)$/) { # w/ serotype
            $cur_str    = $1;   # Strain name
            $cur_stype  = $1;    # Serotype, if possible
        }
        elsif ($org =~ /^Influenza.+?\((.+?)\)/) { # w/o serotype
            $cur_str    = $1;
            # $cur_stype  = '';
        }
        else {
            warn "[ERROR] Unmatched organism:\t '", $org, "'.\n";
            # next;
        }

        # Debug
        # say "cur_str\t--+> ", $cur_str;

        $cur_date   = parse_str_date($cur_str) // '';

        # If there already were values of these fileds, do not touch it
        # The 'genotype' field is ALWAYS blank, 
        # so use 'genotype' field for A, B, C or D TYPE
        my $sql_str = 'UPDATE virus SET genotype = ' . 
            $dbh->quote( $cur_gtype ) . ', ';

        if ( ! $rh_row->{'strain'} ) {  # No 'strain' value
            $sql_str = $sql_str . ' strain = ' . 
                        $dbh->quote( $cur_str ) . ', ';
        }
        if ( ! $rh_row->{'serotype'} ) { # No 'serotype' value
            $sql_str = $sql_str . ' serotype = ' . 
                        $dbh->quote( $cur_stype ) . ', ';
        }
        if ( ! $rh_row->{'collect_date'} ) {# No 'collect_date' value
            $sql_str = $sql_str . ' collect_date = ' . 
                        $dbh->quote( $cur_date ) . ', ';
        }

        $sql_str    =~ s/,\s*$//;  # Remove tailing ','

        $sql_str    = $sql_str . ' WHERE id = ' . $dbh->quote( $vir_id );

        say "SQL\t--+> ", $sql_str;

        eval {
            my $sth = $dbh->prepare($sql_str);
            $sth->execute();
        };
        if ($@) {
            warn "[ERROR] Update table 'virus' in id '$vir_id' failed!\n";
            warn "[ERROR] ", $@, "\n";

            next;
        }
        else {
            $num_upd_vir++;
        }
    }

    return $num_upd_vir;
}

=pod

  Name:     parse_str_date
  Usage:    parse_str_date($str)
  Function: Parse strain name and fetch collection date
  Args:     Strain name, a string
  Returns:  An string of digits.
            An empty string ('') for no date information.
            undef for any errors.
=cut

sub parse_str_date {
    my ($str)   = @_;

    return unless $str;

    my $cdate;

    if ($str =~ /\/(\d{2,4})$/) {
        $cdate  = $1;    
    }
    else {
        return '';
    }

    # For 2-digit year, in MySQL
    # 00 - 69   ==> 2000 - 2069
    # 70 - 99   ==> 1970 - 1999
    if (length($cdate) == 2) {
        if ($cdate >= 0 and $cdate <=20) { # i.e., 2000-2020
            $cdate  = '20' . $cdate;
        }
        else {  # i.e., 19xx
            $cdate  = '19' . $cdate;
        }
    }
    elsif (length($cdate) == 3) {   # 3-digits ?
        return '';
    }
    else {
        #
    }

    return $cdate;
}
