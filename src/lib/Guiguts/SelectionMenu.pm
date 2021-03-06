package Guiguts::SelectionMenu;
use strict;
use warnings;

BEGIN {
    use Exporter();
    our ( @ISA, @EXPORT );
    @ISA    = qw(Exporter);
    @EXPORT = qw(&case &surround &surroundit &flood &floodfill &indent
      &selectrewrap &wrapper &alignpopup &asciibox_popup &blockrewrap &rcaligntext &tocalignselection);
}

my $blockwraptypes = quotemeta '#iI';    # Blockquotes & index allow user to specify left/first/right margins

sub wrapper {
    my ( $leftmargin, $firstmargin, $rightmargin, $paragraph, $rwhyphenspace ) = @_;
    return $paragraph
      if ( $paragraph =~ m|^\x7f*[$::allblocktypes]/\x7f*\n\x7f*$|
        || $paragraph =~ m|^\x7f*/[$::allblocktypes]\x7f*\n\x7f*$|
        || $paragraph =~ m|^\x7f*$| );
    if ( $::rewrapalgo == 1 ) {
        return greedy_wrapper( $leftmargin, $firstmargin, $rightmargin, $paragraph,
            $rwhyphenspace );
    } elsif ( $::rewrapalgo == 2 ) {
        return knuth_wrapper( $leftmargin, $firstmargin, $rightmargin, $paragraph, $rwhyphenspace );
    }
}

sub greedy_wrapper {
    my @words         = ();
    my $word          = '';
    my $line          = '';
    my $leftmargin    = shift;
    my $firstmargin   = shift;
    my $rightmargin   = shift;
    my $paragraph     = shift;
    my $rwhyphenspace = shift;
    $rightmargin++;
    $paragraph =~ s/-\n/-/g unless $rwhyphenspace;
    $paragraph =~ s/\n/ /g;
    return ("\n") unless ($paragraph);
    @words     = split /\s+/, $paragraph;
    $paragraph = '';
    $line      = ' ' x $firstmargin;

    while (@words) {
        $word = shift @words;
        next unless defined $word and length $word;
        if ( $word =~ /\/[$blockwraptypes]/ ) {    # Get margins for blockwrap types
            $firstmargin = $leftmargin = $::blocklmargin if $word =~ /\/#/;    # blockquote has its own default
                                                                               # Check if there are any parameters following blockwrap markup
            if ( $word =~ /^\x7f*\/[$blockwraptypes]\x8A(\d+)/ ) {
                if ( length $1 ) {
                    $leftmargin  = $1;
                    $firstmargin = $leftmargin;
                }
            }
            if ( $word =~ /^\x7f*\/[$blockwraptypes]\x8A(\d+)?(\.)(\d+)/ ) {
                if ( length $3 ) { $firstmargin = $3; }
            }
            if ( $word =~ /^\x7f*\/[$blockwraptypes]\x8A(\d+)?(\.)?(\d+)?,(\d+)/ ) {
                if ($4) { $rightmargin = $4 + 1; }                             # needs +1 to match $rightmargin++ above
            }
            $line =~ s/\s$//;
            if ( $line =~ /\S/ ) {
                $paragraph .= $line . "\n" . $word . "\n";
            } else {
                $paragraph .= $word . "\n";
            }
            $line = ' ' x $firstmargin;
            next;
        }
        if ( $word =~ /[$blockwraptypes]\// ) {
            $line =~ s/ $//;                                                   # remove trailing space
            $paragraph .= $line . "\n" if $line;
            $paragraph .= $word . "\n";
            $leftmargin = $::lmargin - 1;
            $line       = '';
            next;
        }
        my $thisline = $line . $word;
        $thisline =~ s/<\/?[^>]+?>//g;                                         #ignore HTML markup when rewrapping
        if ( length($thisline) < $rightmargin ) {
            $line .= $word . ' ';
        } else {
            if ( $line =~ /\S/ ) {
                $line =~ s/\s$//;
                $paragraph .= $line . "\n";
                $line = ' ' x $leftmargin;
                $line .= $word . ' ';
            } else {
                $paragraph .= $line . $word . "\n";
                $line = ' ' x $leftmargin;
            }
        }
        unless ( scalar(@words) ) {
            $line =~ s/\s$//;
            $paragraph .= "$line\n";
            last;
        }
    }
    if ( $paragraph =~ /-[$::allblocktypes]\// ) {    # Trap bug when there is a hyphen at the end of a block
        $paragraph =~ s/\n(\S+)-([$::allblocktypes]\/)/ $1-\n$2/;
    }
    return ($paragraph);
}

sub knuth_wrapper {
    my ( $leftmargin, $firstmargin, $rightmargin, $paragraph, $rwhyphenspace ) = @_;
    my ( $pre, $post ) = ( '', '' );

    # if open rewrap markup, remove, then prepend once rewrapped
    if    ( $paragraph =~ s|^(\x7f*/[$blockwraptypes]\[[0-9.,]+\])|| ) { $pre = "$1\n"; }
    elsif ( $paragraph =~ s|^(\x7f*/[$blockwraptypes])|| )             { $pre = "$1\n"; }

    # if close rewrap markup, remove (including any newline), then append once rewrapped
    if ( $paragraph =~ s|([$blockwraptypes]/\x7f*)(\n?)$|| ) { $post = "$1$2"; }
    my $maxwidth = $rightmargin;
    my $optwidth = $rightmargin - $::rmargindiff;
    $paragraph =~ s/-\n/-/g unless $rwhyphenspace;
    $paragraph =~ s/\n/ /g;
    my $reflowed = ::reflow_string(
        $paragraph,
        maximum       => $maxwidth,
        optimum       => $optwidth,
        indent1       => ' ' x $firstmargin,
        indent2       => ' ' x $leftmargin,
        frenchspacing => 'y',
        semantic      => 0,
        namebreak     => 0,
        sentence      => 0,
        independent   => 0,
        dependent     => 0,
        shortlast     => 0,
        connpenalty   => 0,
    );
    $reflowed =~ s/ *$//;
    return $pre . $reflowed . $post;
}

sub selectrewrap {

    #my ( $textwindow, $seepagenums, $scannos_highlighted ) = @_;
    my $textwindow = $::textwindow;
    ::hidepagenums();
    ::savesettings();
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    my $thisblockstart;
    my $start;
    my $scannosave = $::scannos_highlighted;
    $::scannos_highlighted = 0;
    $::operationinterrupt  = 0;

    if ( $range_total == 0 ) {
        return;
    } else {
        $textwindow->addGlobStart;
        my $end = pop(@ranges);    #get the end index of the selection
        $start = pop(@ranges);     #get the start index of the selection
        my @marklist = $textwindow->dump( -mark, $start, $end );    #see if there any page markers set
        my ( $markname, @savelist, $markindex );
        while (@marklist) {                                         #save the pagemarkers if they have been set
            shift @marklist;
            $markname  = shift @marklist;
            $markindex = shift @marklist;
            if ( $markname =~ /Pg\S+/ ) {
                $textwindow->insert( $markindex, "\x7f" );          #mark the page breaks for rewrapping
                push @savelist, $markname;
            }
        }
        while ( $textwindow->get($start) =~ /^\s*\n/ ) {            #if the selection starts on a blank line
            $start = $textwindow->index("$start+1c")                #advance the selection start until it isn't.
        }
        while ( $textwindow->get("$end+1c") =~ /^\s*\n/ ) {         #if the selection ends at the end of a line but not over it
            $end = $textwindow->index("$end+1c")                    #advance the selection end until it does. (traps odd spaces
        }    #at paragraph end bug)
        $thisblockstart = $start;
        my $thisblockend   = $end;
        my $indentblockend = $end;
        my $inblock        = 0;
        my $infront        = 0;
        my $enableindent;
        my $fblock      = 0;
        my $leftmargin  = $::blocklmargin;
        my $rightmargin = $::blockrmargin;
        my $firstmargin = $::blocklmargin;
        my ( $rewrapped, $initial_tab, $subsequent_tab, $spaces );
        my $indent = 0;
        my $offset = 0;
        my $poem   = 0;
        my $textline;
        my $lastend = $start;
        my ( $sr, $sc, $er, $ec, $line );
        my $textend      = $textwindow->index('end');
        my $toplineblank = 0;
        my $selection;

        if ( $textend eq $end ) {
            $textwindow->tagAdd( 'blockend', "$end-1c" )    #set a marker at the end of the selection, or one charecter less
        } else {                                            #if the selection ends at the text end
            $textwindow->tagAdd( 'blockend', $end );
        }
        if ( $textwindow->get( '1.0', '1.end' ) eq '' ) {    #trap top line delete bug
            $toplineblank = 1;
        }
        ::opstop();
        $spaces = 0;

        # main while loop
        while (1) {
            $indent = $::defaultindent;
            $thisblockend =
              $textwindow->search( '-regex', '--', '(^[\x7f]*$)|([' . $blockwraptypes . ']/)',
                $thisblockstart, $end );                     # find end of paragraph or end of markup
                                                             # if two start rewrap block markers aren't separated by a blank line, just let it become added
            $thisblockend = $thisblockstart
              if ( $textwindow->get( "$thisblockstart +1l", "$thisblockstart +1l+2c" ) =~
                /^\/[$::allblocktypes]$/ );

            if ($thisblockend) {
                $thisblockend = $textwindow->index( $thisblockend . ' lineend' );
            } else {
                $thisblockend = $end;
            }
            ;                                                #or end of text if end of selection
            $selection = $textwindow->get( $thisblockstart, $thisblockend )
              if $thisblockend;                              #get the paragraph of text
            unless ($selection) {
                $thisblockstart = $thisblockend;
                $thisblockstart = $textwindow->index("$thisblockstart+1c");
                last
                  if ( $textwindow->compare( $thisblockstart, '>=', $end ) );
                last if $::operationinterrupt;
                next;
            }
            last

              if ( ( $thisblockend eq $lastend )
                || ( $textwindow->compare( $thisblockend, '<', $lastend ) ) );    #quit if the search isn't advancing
            $textwindow->see($thisblockend);
            $textwindow->update;

            # Check for block types that support blockwrap
            if ( $selection =~ /^\x7f*\/[$blockwraptypes]/ ) {
                $::blockwrap = 1;
                if ( $selection =~ /^\x7f*\/\#/ ) {
                    $leftmargin  = $::blocklmargin;
                    $firstmargin = $::blocklmargin;
                    $rightmargin = $::blockrmargin;
                }

                # Check if there are any parameters following blockwrap markup [n...
                if ( $selection =~ /^\x7f*\/[$blockwraptypes]\[(\d+)/ ) {    #check for block rewrapping with parameter markup
                    $leftmargin  = $1;
                    $firstmargin = $leftmargin;
                }

                # [n.n...
                if ( $selection =~ /^\x7f*\/[$blockwraptypes]\[(\d+)?(\.)(\d+)/ ) {
                    $firstmargin = $3;
                }

                # [n.n,n...
                if ( $selection =~ /^\x7f*\/[$blockwraptypes]\[(\d+)?(\.)?(\d+)?,(\d+)/ ) {
                    $rightmargin = $4;
                }
            }

            # if selection is /*, /L, or /l
            if ( $selection =~ /^\x7f*\/[\*Ll]/ ) {
                $inblock      = 1;
                $enableindent = 1;
            }    #check for no rewrap markup
                 # if there are any parameters /*[n
            if ( $selection =~ /^\x7f*\/\*\[(\d+)/ ) { $indent = $1 }

            # if selection begins /p or /P
            if ( $selection =~ /^\x7f*\/[pP]/ ) {
                $inblock      = 1;
                $enableindent = 1;
                $poem         = 1;
                $indent       = $::poetrylmargin;
            }

            # if selection begins /x or /X or /$
            if ( $selection =~ /^\x7f*\/[Xx\$]/ ) { $inblock = 1 }

            # if selection begins /f or /F
            if ( $selection =~ /^\x7f*\/[fF]/ ) {
                $inblock = 1;
            }
            $textwindow->markSet( 'rewrapend', $thisblockend );    #Set a mark at the end of the text so it can be found after rewrap
            unless ( $selection =~ /^\x7f*\s*?(\*\s*){4}\*/ ) {    #skip rewrap if paragraph is a thought break
                if ($inblock) {
                    if ($enableindent) {
                        $indentblockend = $textwindow->search( '-regex', '--',
                            '^\x7f*[pP\*Ll]\/', $thisblockstart, $end );
                        $indentblockend = $indentblockend || $end;
                        $textwindow->markSet( 'rewrapend', $indentblockend );
                        unless ($offset) { $offset = 0 }
                        ( $sr, $sc ) = split /\./, $thisblockstart;
                        ( $er, $ec ) = split /\./, $indentblockend;
                        unless ($offset) {
                            $offset = 100;
                            for my $line ( $sr + 1 .. $er - 1 ) {
                                $textline = $textwindow->get( "$line.0", "$line.end" );
                                if ($textline) {
                                    $textwindow->search(
                                        '-regexp',
                                        '-count' => \$spaces,
                                        '--', '^\s+', "$line.0", "$line.end"
                                    );
                                    unless ($spaces) { $spaces = 0 }
                                    if ( $spaces < $offset ) {
                                        $offset = $spaces;
                                    }
                                    $spaces = 0;
                                }
                            }
                            $indent = $indent - $offset;
                        }
                        for my $line ( $sr .. $er - 1 ) {
                            $textline = $textwindow->get( "$line.0", "$line.end" );
                            next
                              if ( ( $textline =~ /^\x7f*\/[pP\*Ll]/ )
                                || ( $textline =~ /^\x7f*[pP\*LlFf]\// ) );
                            if ( $enableindent and $fblock == 0 ) {
                                $textwindow->insert( "$line.0", ( ' ' x $indent ) )
                                  if ( $indent > 0 );
                                if ( $indent < 0 ) {
                                    if (
                                        $textwindow->get( "$line.0", "$line.@{[abs $indent]}" ) =~
                                        /\S/ ) {
                                        while ( $textwindow->get("$line.0") eq ' ' ) {
                                            $textwindow->delete("$line.0");
                                        }
                                    } else {
                                        $textwindow->delete( "$line.0", "$line.@{[abs $indent]}" );
                                    }
                                }
                            } else {
                            }
                        }
                        $indent       = 0;
                        $offset       = 0;
                        $enableindent = 0;
                        $poem         = 0;
                        $inblock      = 0;
                    }
                } else {
                    $selection =~ s/<i>/\x8d/g;     #convert some characters that will interfere with rewrap
                    $selection =~ s/<\/i>/\x8e/g;
                    if ( $::rewrapalgo == 1 ) {
                        $selection =~ s/\[/\x8A/g;
                        $selection =~ s/\]/\x9A/g;
                        $selection =~ s/\(/\x9d/g;
                        $selection =~ s/\)/\x98/g;
                    }
                    if ($::blockwrap) {
                        $rewrapped = wrapper(
                            $leftmargin, $firstmargin, $rightmargin,
                            $selection,  $::rwhyphenspace
                        );
                    } else {    #rewrap the paragraph
                        $rewrapped = wrapper( $::lmargin, $::lmargin, $::rmargin,
                            $selection, $::rwhyphenspace );
                    }
                    $rewrapped =~ s/\x8d/<i>/g;     #convert the characters back
                    $rewrapped =~ s/\x8e/<\/i>/g;
                    if ( $::rewrapalgo == 1 ) {
                        $rewrapped =~ s/\x8A/\[/g;
                        $rewrapped =~ s/\x9A/\]/g;
                        $rewrapped =~ s/\x98/\)/g;
                        $rewrapped =~ s/\x9d/\(/g;
                    }
                    $textwindow->delete( $thisblockstart, $thisblockend );    #delete the original paragraph
                    $textwindow->insert( $thisblockstart, $rewrapped );       #insert the rewrapped paragraph
                    my @endtemp = $textwindow->tagRanges('blockend');         #find the end of the rewrapped text
                    $end = shift @endtemp;
                }
            }
            if ( $selection =~ /^\x7f*[XxFf\$]\//m ) {
                $inblock      = 0;
                $indent       = 0;
                $offset       = 0;
                $enableindent = 0;
                $poem         = 0;
            }
            if ( $selection =~ /\x7f*[$blockwraptypes]\// ) { $::blockwrap = 0 }
            last unless $end;
            $thisblockstart = $textwindow->index('rewrapend');             #advance to the next paragraph
            $lastend        = $textwindow->index("$thisblockstart+1c");    #track where the end of the last paragraph was
            while (1) {
                $thisblockstart = $textwindow->index("$thisblockstart+1l");    #if there are blank lines before the next paragraph, advance past them
                last
                  if ( $textwindow->compare( $thisblockstart, '>=', 'end' ) );
                next
                  if ( $textwindow->get( $thisblockstart, "$thisblockstart lineend" ) eq '' );
                last;
            }
            $::blockwrap = 0
              if $::operationinterrupt;                                        #reset blockwrap if rewrap routine is interrupted
            last if $::operationinterrupt;                                     #then quit
            last
              if ( $thisblockstart eq $end );                                  #quit if next paragrapn starts at end of selection
            ::update_indicators();                                             # update line and page numbers
        }
        ::killstoppop();
        $::operationinterrupt = 0;
        $textwindow->focus;
        $textwindow->update;
        $textwindow->Busy( -recurse => 1 );
        if (@savelist) {                                                       #if there are saved page markers
            while (@savelist) {                                                #reinsert them
                $markname  = shift @savelist;
                $markindex = $textwindow->search( '-regex', '--', '\x7f', '1.0', 'end' );
                $textwindow->delete($markindex);                               #then remove the page markers
                $textwindow->markSet( $markname, $markindex );
                $textwindow->markGravity( $markname, 'left' );
            }
        }
        if ( $start eq '1.0' ) {                                               #reinsert deleted top line if it was removed
            if ( $toplineblank == 1 ) {                                        #(kinda half assed but it works)
                $textwindow->insert( '1.0', "\n" );
            }
        }
        $textwindow->tagRemove( 'blockend', '1.0', 'end' );
    }
    while (1) {
        $thisblockstart = $textwindow->search( '-regexp', '--', '^[\x7f\s]+$', '1.0', 'end' );
        last unless $thisblockstart;
        $textwindow->delete( $thisblockstart, "$thisblockstart lineend" );
    }
    $textwindow->see($start);
    $textwindow->addGlobEnd;

    #$scannos_highlighted = $scannosave;
    $textwindow->Unbusy( -recurse => 1 );
}

sub aligntext {
    my ( $textwindow, $alignstring ) = @_;
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    if ( $range_total == 0 ) {
        return;
    } else {
        my $textindex = 0;
        my ( $linenum, $line, $sr, $sc, $er, $ec, $r, $c, @indexpos );
        my $end   = pop(@ranges);
        my $start = pop(@ranges);
        $textwindow->addGlobStart;
        ( $sr, $sc ) = split /\./, $start;
        ( $er, $ec ) = split /\./, $end;
        for my $linenum ( $sr .. $er - 1 ) {
            $indexpos[$linenum] =
              $textwindow->search( '--', $alignstring, "$linenum.0 -1c", "$linenum.end" );
            if ( $indexpos[$linenum] ) {
                ( $r, $c ) = split /\./, $indexpos[$linenum];
            } else {
                $c = -1;
            }
            if ( $c > $textindex ) { $textindex = $c }
            $indexpos[$linenum] = $c;
        }
        for my $linenum ( $sr .. $er ) {
            $indexpos[$linenum] = 0 unless defined $indexpos[$linenum];
            if ( $indexpos[$linenum] > (-1) ) {
                $textwindow->insert( "$linenum.0", ( ' ' x ( $textindex - $indexpos[$linenum] ) ) );
            }
        }
        $textwindow->addGlobEnd;
    }
}

sub asciibox {
    my ( $textwindow, $asciiwrap, $asciiwidth, $ascii, $asciijustify ) = @_;
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    if ( $range_total == 0 ) {
        return;
    } else {
        my ( $linenum, $line, $sr, $sc, $er, $ec, $lspaces, $rspaces );
        my $end   = pop(@ranges);
        my $start = pop(@ranges);
        $textwindow->markSet( 'asciistart', $start );
        $textwindow->markSet( 'asciiend',   $end );
        my $saveleft  = $::lmargin;
        my $saveright = $::rmargin;
        $textwindow->addGlobStart;
        $::lmargin = 0;
        $::rmargin = ( $asciiwidth - 4 );
        ::selectrewrap() unless $asciiwrap;
        $::lmargin = $saveleft;
        $::rmargin = $saveright;
        $textwindow->insert( 'asciistart',
            ${$ascii}[0] . ( ${$ascii}[1] x ( $asciiwidth - 2 ) ) . ${$ascii}[2] . "\n" );
        $textwindow->insert( 'asciiend',
            "\n" . ${$ascii}[6] . ( ${$ascii}[7] x ( $asciiwidth - 2 ) ) . ${$ascii}[8] . "\n" );
        $start = $textwindow->index('asciistart');
        $end   = $textwindow->index('asciiend');
        ( $sr, $sc ) = split /\./, $start;
        ( $er, $ec ) = split /\./, $end;

        for my $linenum ( $sr .. $er - 2 ) {
            $line = $textwindow->get( "$linenum.0", "$linenum.end" );
            $line =~ s/^\s*//;
            $line =~ s/\s*$//;
            if ( $asciijustify eq 'left' ) {
                $lspaces = 1;
                $rspaces = ( $asciiwidth - 3 ) - length($line);
            } elsif ( $asciijustify eq 'center' ) {
                $lspaces = ( $asciiwidth - 2 ) - length($line);
                if ( $lspaces % 2 ) {
                    $rspaces = ( $lspaces / 2 ) + .5;
                    $lspaces = $rspaces - 1;
                } else {
                    $rspaces = $lspaces / 2;
                    $lspaces = $rspaces;
                }
            } elsif ( $asciijustify eq 'right' ) {
                $rspaces = 1;
                $lspaces = ( $asciiwidth - 3 ) - length($line);
            }
            $line = ${$ascii}[3] . ( ' ' x $lspaces ) . $line . ( ' ' x $rspaces ) . ${$ascii}[5];
            $textwindow->delete( "$linenum.0", "$linenum.end" );
            $textwindow->insert( "$linenum.0", $line );
        }
        $textwindow->addGlobEnd;
    }
}

sub case {
    ::savesettings();
    my ( $textwindow, $marker ) = @_;
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    my $done        = '';
    if ( $range_total == 0 ) {
        return;
    } else {
        $textwindow->addGlobStart;
        while (@ranges) {
            my $end            = pop(@ranges);
            my $start          = pop(@ranges);
            my $thisblockstart = $start;
            my $thisblockend   = $end;
            my $selection      = $textwindow->get( $thisblockstart, $thisblockend );
            my @words          = ();
            if ( $marker eq 'uc' ) {
                $done = uc($selection);
            } elsif ( $marker eq 'lc' ) {
                $done = lc($selection);
            } elsif ( $marker eq 'sc' ) {
                $done = lc($selection);
                $done =~ s/(^\W*\w)/\U$1\E/;
            } elsif ( $marker eq 'tc' ) {
                $done = ::titlecase($selection);
            }
            $textwindow->replacewith( $start, $end, $done );
        }
        $textwindow->addGlobEnd;
    }
}

sub surround {
    my ( $textwindow, $top ) = ( $::textwindow, $::top );
    if ( defined( $::lglobal{surpop} ) ) {
        $::lglobal{surpop}->deiconify;
        $::lglobal{surpop}->raise;
        $::lglobal{surpop}->focus;
    } else {
        $::lglobal{surpop} = $top->Toplevel;
        $::lglobal{surpop}->title('Surround With');
        my $f = $::lglobal{surpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        $f->Label( -text => "Surround the selection with:\n\\n will be replaced with a newline.", )
          ->pack(
            -side   => 'top',
            -pady   => 5,
            -padx   => 2,
            -anchor => 'n'
          );
        my $f1      = $::lglobal{surpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my $surstrt = $f1->Entry(
            -textvariable => \$::lglobal{surstrt},
            -width        => 8,
            -background   => $::bkgcolor,
            -font         => $::lglobal{font},
            -relief       => 'sunken',
        )->pack(
            -side   => 'left',
            -pady   => 5,
            -padx   => 2,
            -anchor => 'n'
        );
        my $surend = $f1->Entry(
            -textvariable => \$::lglobal{surend},
            -width        => 8,
            -background   => $::bkgcolor,
            -font         => $::lglobal{font},
            -relief       => 'sunken',
        )->pack(
            -side   => 'left',
            -pady   => 5,
            -padx   => 2,
            -anchor => 'n'
        );
        my $f2    = $::lglobal{surpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my $gobut = $f2->Button(
            -activebackground => $::activecolor,
            -command          => sub {
                ::surroundit( $::lglobal{surstrt}, $::lglobal{surend}, $textwindow );
            },
            -text  => 'Surround',
            -width => 16
        )->pack(
            -side   => 'top',
            -pady   => 5,
            -padx   => 2,
            -anchor => 'n'
        );
        ::initialize_popup_with_deletebinding('surpop');
        $surstrt->insert( 'end', '_' ) unless ( $surstrt->get );
        $surend->insert( 'end', '_' )  unless ( $surend->get );
    }
}

sub surroundit {
    my ( $pre, $post, $textwindow ) = @_;
    $pre  =~ s/\\n/\n/;
    $post =~ s/\\n/\n/;
    my @ranges = $textwindow->tagRanges('sel');
    unless (@ranges) {
        push @ranges, $textwindow->index('insert');
        push @ranges, $textwindow->index('insert');
    }
    $textwindow->addGlobStart;
    while (@ranges) {
        my $end   = pop(@ranges);
        my $start = pop(@ranges);
        $textwindow->replacewith( $start, $end, $pre . $textwindow->get( $start, $end ) . $post );
    }
    $textwindow->addGlobEnd;
}

sub flood {

    #my ( $textwindow, $top, $floodpop, $font, $activecolor, $icon ) = @_;
    my $top        = $::top;
    my $textwindow = $::textwindow;
    if ( defined( $::lglobal{floodpop} ) ) {
        $::lglobal{floodpop}->deiconify;
        $::lglobal{floodpop}->raise;
        $::lglobal{floodpop}->focus;
    } else {
        $::lglobal{floodpop} = $top->Toplevel;
        $::lglobal{floodpop}->title('Flood Fill');
        my $f = $::lglobal{floodpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        $f->Label( -text => "Flood fill selection with string:\n(Blank will default to spaces.)", )
          ->pack( -side => 'top', -pady => 5, -padx => 2, -anchor => 'n' );
        my $f1 = $::lglobal{floodpop}->Frame->pack(
            -side   => 'top',
            -anchor => 'n',
            -expand => 'y',
            -fill   => 'x'
        );
        my $floodch = $f1->Entry(
            -background   => $::bkgcolor,
            -font         => $::lglobal{font},
            -relief       => 'sunken',
            -textvariable => \$::lglobal{ffchar},
        )->pack(
            -side   => 'left',
            -pady   => 5,
            -padx   => 2,
            -anchor => 'w',
            -expand => 'y',
            -fill   => 'x'
        );
        my $f2    = $::lglobal{floodpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my $gobut = $f2->Button(
            -activebackground => $::activecolor,
            -command          => sub { floodfill( $textwindow, $::lglobal{ffchar} ) },
            -text             => 'Flood Fill',
            -width            => 16
        )->pack( -side => 'top', -pady => 5, -padx => 2, -anchor => 'n' );
        ::initialize_popup_with_deletebinding('floodpop');
    }
}

sub floodfill {
    my ( $textwindow, $ffchar ) = @_;
    my @ranges = $textwindow->tagRanges('sel');
    return unless @ranges;
    $ffchar = ' ' unless length $ffchar;
    $textwindow->addGlobStart;
    while (@ranges) {
        my $end       = pop(@ranges);
        my $start     = pop(@ranges);
        my $selection = $textwindow->get( $start, $end );
        my $temp      = substr( $ffchar x ( ( ( length $selection ) / ( length $ffchar ) ) + 1 ),
            0, ( length $selection ) );
        chomp $selection;
        my @temparray = split( /\n/, $selection );
        my $replacement;
        for (@temparray) {
            $replacement .= substr( $temp, 0, ( length $_ ), '' );
            $replacement .= "\n";
        }
        chomp $replacement;
        $textwindow->replacewith( $start, $end, $replacement );
    }
    $textwindow->addGlobEnd;
}

sub indent {
    my ( $textwindow, $indent ) = @_;
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    $::operationinterrupt = 0;
    if ( $range_total == 0 ) {
        return;
    } else {
        my @selarray;
        if ( $indent eq 'up' ) { @ranges = reverse @ranges }
        $textwindow->addGlobStart;
        while (@ranges) {
            my $end            = pop(@ranges);
            my $start          = pop(@ranges);
            my $thisblockstart = int($start) . '.0';
            my $thisblockend   = int($end) . '.0';
            my $index          = $thisblockstart;
            if ( $thisblockstart == $thisblockend ) {
                my $char;
                if ( $indent eq 'in' ) {
                    if ( $textwindow->compare( $end, '==', "$end lineend" ) ) {
                        $char = ' ';
                    } else {
                        $char = $textwindow->get($end);
                        $textwindow->delete($end);
                    }
                    $textwindow->insert( $start, $char )
                      unless ( $textwindow->get( $start, "$start lineend" ) =~ /^$/ );
                    $end = "$end+1c"
                      unless ( $textwindow->get( $end, "$end lineend" ) =~ /^$/ );
                    push @selarray, ( "$start+1c", $end );
                } elsif ( $indent eq 'out' ) {
                    if ( $textwindow->compare( $start, '==', "$start linestart" ) ) {
                        push @selarray, ( $start, $end );
                        next;
                    } else {
                        $char = $textwindow->get("$start-1c");
                        $textwindow->insert( $end, $char );
                        $textwindow->delete("$start-1c");
                        push @selarray, ( "$start-1c", "$end-1c" );
                    }
                }
            } else {
                while ( $index <= $thisblockend ) {
                    if ( $indent eq 'in' ) {
                        $textwindow->insert( $index, ' ' )
                          unless ( $textwindow->get( $index, "$index lineend" ) =~ /^$/ );
                    } elsif ( $indent eq 'out' ) {
                        if ( $textwindow->get( $index, "$index+1c" ) eq ' ' ) {
                            $textwindow->delete( $index, "$index+1c" );
                        }
                    }
                    $index++;
                    $index .= '.0';
                }
                push @selarray, ( $thisblockstart, "$thisblockend lineend" );
            }
            if ( $indent eq 'up' ) {
                my $temp = $end, $end = $start;
                $start = $temp;
                if ( $textwindow->compare( "$start linestart", '==', '1.0' ) ) {
                    push @selarray, ( $start, $end );
                    push @selarray, @ranges;
                    last;
                } else {
                    while ( $textwindow->compare( "$end-1l", '>=', "$end-1l lineend" ) ) {
                        $textwindow->insert( "$end-1l lineend", ' ' );
                    }
                    my $templine = $textwindow->get( "$start-1l", "$end-1l" );
                    $textwindow->replacewith( "$start-1l", "$end-1l",
                        ( $textwindow->get( $start, $end ) ) );
                    push @selarray, ( "$start-1l", "$end-1l" );
                    while (@ranges) {
                        $start = pop(@ranges);
                        $end   = pop(@ranges);
                        $textwindow->replacewith( "$start-1l", "$end-1l",
                            ( $textwindow->get( $start, $end ) ) );
                        push @selarray, ( "$start-1l", "$end-1l" );
                    }
                    $textwindow->replacewith( $start, $end, $templine );
                }
            } elsif ( $indent eq 'dn' ) {
                if ( $textwindow->compare( "$end+1l", '>=', $textwindow->index('end') ) ) {
                    push @selarray, ( $start, $end );
                    push @selarray, @ranges;
                    last;
                } else {
                    while ( $textwindow->compare( "$end+1l", '>=', "$end+1l lineend" ) ) {
                        $textwindow->insert( "$end+1l lineend", ' ' );
                    }
                    my $templine = $textwindow->get( "$start+1l", "$end+1l" );
                    $textwindow->replacewith( "$start+1l", "$end+1l",
                        ( $textwindow->get( $start, $end ) ) );
                    push @selarray, ( "$start+1l", "$end+1l" );
                    while (@ranges) {
                        $end   = pop(@ranges);
                        $start = pop(@ranges);
                        $textwindow->replacewith( "$start+1l", "$end+1l",
                            ( $textwindow->get( $start, $end ) ) );
                        push @selarray, ( "$start+1l", "$end+1l" );
                    }
                    $textwindow->replacewith( $start, $end, $templine );
                }
            }
            $textwindow->focus;
            $textwindow->tagRemove( 'sel', '1.0', 'end' );
        }
        while (@selarray) {
            my $end   = pop(@selarray);
            my $start = pop(@selarray);
            $textwindow->tagAdd( 'sel', $start, $end );
        }
        $textwindow->addGlobEnd;
    }
}

sub alignpopup {
    my $textwindow = $::textwindow;
    my $top        = $::top;
    if ( defined( $::lglobal{alignpop} ) ) {
        $::lglobal{alignpop}->deiconify;
        $::lglobal{alignpop}->raise;
        $::lglobal{alignpop}->focus;
    } else {
        $::lglobal{alignpop} = $top->Toplevel;
        $::lglobal{alignpop}->title('Align text');
        my $f = $::lglobal{alignpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        $f->Label( -text => 'String to align on (first occurence)', )
          ->pack( -side => 'top', -pady => 5, -padx => 2, -anchor => 'n' );
        my $f1 = $::lglobal{alignpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        $f1->Entry(
            -width        => 8,
            -background   => $::bkgcolor,
            -font         => $::lglobal{font},
            -relief       => 'sunken',
            -textvariable => \$::lglobal{alignstring},
        )->pack( -side => 'top', -pady => 5, -padx => 2, -anchor => 'n' );
        my $gobut = $f1->Button(
            -activebackground => $::activecolor,
            -command          => [
                sub {
                    aligntext( $textwindow, $::lglobal{alignstring} );
                }
            ],
            -text  => 'Align selected text',
            -width => 16
        )->pack( -side => 'top', -pady => 5, -padx => 2, -anchor => 'n' );
        ::initialize_popup_with_deletebinding('alignpop');
    }
}

sub blockrewrap {
    my $textwindow = $::textwindow;
    $::blockwrap = 1;
    selectrewrap( $textwindow, $::lglobal{seepagenums}, $::scannos_highlighted, $::rwhyphenspace );
    $::blockwrap = 0;
}

sub asciibox_popup {
    my $textwindow = $::textwindow;
    my $top        = $::top;
    ::hidepagenums();
    if ( defined( $::lglobal{asciiboxpop} ) ) {
        $::lglobal{asciiboxpop}->deiconify;
        $::lglobal{asciiboxpop}->raise;
        $::lglobal{asciiboxpop}->focus;
    } else {
        $::lglobal{asciiboxpop} = $top->Toplevel;
        $::lglobal{asciiboxpop}->title('ASCII Boxes');
        my $f = $::lglobal{asciiboxpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        $f->Label( -text => 'ASCII Drawing Characters', )
          ->pack( -side => 'top', -pady => 2, -padx => 2, -anchor => 'n' );
        my $f5 = $::lglobal{asciiboxpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my ( $row, $col );
        for ( 0 .. 8 ) {
            next if $_ == 4;
            $row = int $_ / 3;
            $col = $_ % 3;
            $f5->Entry(
                -width        => 1,
                -background   => $::bkgcolor,
                -font         => $::lglobal{font},
                -relief       => 'sunken',
                -textvariable => \${ $::lglobal{ascii} }[$_],
            )->grid(
                -row    => $row,
                -column => $col,
                -padx   => 3,
                -pady   => 3
            );
        }
        my $f0     = $::lglobal{asciiboxpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my $wlabel = $f0->Label(
            -width => 16,
            -text  => 'ASCII Box Width',
        )->pack( -side => 'left', -pady => 2, -padx => 2, -anchor => 'n' );
        my $wmentry = $f0->Entry(
            -width        => 6,
            -background   => $::bkgcolor,
            -relief       => 'sunken',
            -textvariable => \$::lglobal{asciiwidth},
        )->pack( -side => 'left', -pady => 2, -padx => 2, -anchor => 'n' );
        my $f1       = $::lglobal{asciiboxpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my $leftjust = $f1->Radiobutton(
            -text        => 'left justified',
            -selectcolor => $::lglobal{checkcolor},
            -variable    => \$::lglobal{asciijustify},
            -value       => 'left',
        )->grid( -row => 2, -column => 1, -padx => 1, -pady => 2 );
        my $centerjust = $f1->Radiobutton(
            -text        => 'centered',
            -selectcolor => $::lglobal{checkcolor},
            -variable    => \$::lglobal{asciijustify},
            -value       => 'center',
        )->grid( -row => 2, -column => 2, -padx => 1, -pady => 2 );
        my $rightjust = $f1->Radiobutton(
            -selectcolor => $::lglobal{checkcolor},
            -text        => 'right justified',
            -variable    => \$::lglobal{asciijustify},
            -value       => 'right',
        )->grid( -row => 2, -column => 3, -padx => 1, -pady => 2 );
        my $asciiw = $f1->Checkbutton(
            -variable    => \$::lglobal{asciiwrap},
            -selectcolor => $::lglobal{checkcolor},
            -text        => 'Don\'t Rewrap'
        )->grid( -row => 3, -column => 2, -padx => 1, -pady => 2 );
        my $gobut = $f1->Button(
            -activebackground => $::activecolor,
            -command          => sub {
                asciibox(
                    $textwindow,       $::lglobal{asciiwrap}, $::lglobal{asciiwidth},
                    $::lglobal{ascii}, $::lglobal{asciijustify}
                );
            },
            -text  => 'Draw Box',
            -width => 16
        )->grid( -row => 4, -column => 2, -padx => 1, -pady => 2 );
        $::lglobal{asciiboxpop}->resizable( 'no', 'no' );
        ::initialize_popup_with_deletebinding('asciiboxpop');
        $::lglobal{asciiboxpop}->raise;
        $::lglobal{asciiboxpop}->focus;
    }
}

sub rcaligntext {
    my ( $align, $indentval ) = @_;
    my $textwindow  = $::textwindow;
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    my $optrmargin  = $::rmargin - $::rmargindiff;
    return if ( $range_total == 0 );
    my ( $start, $end ) = ::expandselection();
    my $thisblockstart = "$start.0";
    my $thisblockend   = "$end.0";
    my $index          = $thisblockstart;
    $textwindow->addGlobStart;

    while ( $index < $thisblockend ) {
        while ( $textwindow->get( $index, "$index+1c" ) eq ' ' ) {
            $textwindow->delete( $index, "$index+1c" );
        }
        my $line = $textwindow->get( $index, "$index lineend" );
        if ( length($line) < $optrmargin ) {
            my $paddval = $optrmargin - length($line) + $indentval;
            if ( $align eq 'c' ) { $paddval = $paddval / 2; }
            $textwindow->insert( $index, ' ' x $paddval ) unless $line eq '';
        }
        $index++;
        $index .= '.0';
    }
    $textwindow->addGlobEnd;
    $textwindow->focus;
}

sub tocalignselection {
    my ($indentval) = @_;
    $indentval = 0 unless $indentval;
    my $textwindow  = $::textwindow;
    my @ranges      = $textwindow->tagRanges('sel');
    my $range_total = @ranges;
    return if ( $range_total == 0 );
    my ( $start, $end ) = ::expandselection();
    my $thisblockstart = "$start.0";
    my $thisblockend   = "$end.0";
    my $index          = $thisblockstart;
    $textwindow->addGlobStart;

    while ( $index < $thisblockend ) {
        my $line = $textwindow->get( $index, "$index lineend" );
        if ( $line =~ /^(.*)  +(\d+\.?)$/ ) {
            my $len1     = length($1);
            my $len2     = length($2);
            my $spacelen = length($line) - $len1 - $len2;
            if ( $len1 + $len2 + 2 < $::rmargin ) {
                my $paddval = $::rmargin - $len1 - $len2 - $spacelen + $indentval;
                $textwindow->insert( $index . "+$len1 c", ' ' x $paddval );
            }
        }
        $index++;
        $index .= '.0';
    }
    $textwindow->addGlobEnd;
    $textwindow->focus;
}

1;
