package Plugins::SqueezeDSPNativeDSD::UI_Functions;
use strict;
use JSON::XS;
use MIME::Base64;
use File::Copy;
use File::Spec::Functions qw(catdir catfile);  # ADD THIS IMPORT
use File::Basename;

sub filtersQuery {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("query: filters");

    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.filters' ]])) {
        $request->setStatusBadDispatch();
        return;
    }
	# return "Filter_loop" with list of the available filters
	# and "Preset_loop" with list of the available presets
	# (only their short names, not full paths)
    my %filters = getFiltersListNoNone($client, $Plugins::SqueezeDSPNativeDSD::Plugin::pluginImpulsesDataDir, 0);
    my $cnt = 0;
    foreach my $ff(sort { uc($a) cmp uc($b) } keys %filters) {
        $request->addResultLoop('FIRWavFile_loop', $cnt, 0, $ff);
        $cnt++;
    }

    my %presets = getPresetsListNoNone($client, 0);
    $cnt = 0;
    foreach my $ff(sort { uc($a) cmp uc($b) } keys %presets) {
        $request->addResultLoop('Preset_loop', $cnt, 0, $ff);
        $cnt++;
    }

    $request->setStatusDone();
}

sub logsummaryQuery {
    my $request = shift;
    my $client = $request->client();
    my $clientID = $client->id();
    my $tracklimit = 10;
    Plugins::SqueezeDSPNativeDSD::Utils::debug("query: logsummary");

    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.logsummary' ]])) {
        $request->setStatusBadDispatch();
        return;
    }
    
    my $startline = '';
    my $trackcount = 0;
    my @reportlines;
    my @startvalues;

    Plugins::SqueezeDSPNativeDSD::Utils::debug("Opening log file " . $Plugins::SqueezeDSPNativeDSD::Plugin::logfile . " for " . $clientID);
    if (! -e $Plugins::SqueezeDSPNativeDSD::Plugin::logfile) {
        Plugins::SqueezeDSPNativeDSD::Utils::debug("Log file does not exist: $Plugins::SqueezeDSPNativeDSD::Plugin::logfile");
        $request->addResult("trackcount", 0);
        $request->setStatusDone();
        return;
    }

    open(FILE, "<$Plugins::SqueezeDSPNativeDSD::Plugin::logfile") or die("Could not open log file. $!\n");
    while(<FILE>) {
        my($line) = $_;
        chomp($line);
        if (index($line, '=>') != -1 && index($line, $clientID) != -1) {
            $startline = $line;
        }
        if (index($line, 'peak') != -1 && index($line, $clientID) != -1) {
            my @endvalues = split(' ', $line);
            if ($endvalues[3] != 0) {
                @startvalues = split(' ', $startline);
                my %reportrow = (
                    date    => $startvalues[0],
                    time    => $startvalues[1],
                    playerid => $startvalues[2],
                    inputrate => $startvalues[3],
                    outputrate    => $startvalues[6],
                    preamp     => $startvalues[10],    
                    internalgain => $startvalues[14],   # <-- 2026/03/27
    				peakdBfs     => $endvalues[13],
    				inputpeak    => $endvalues[17],     # <-- 2026/03/27
                );
                push @reportlines, \%reportrow;
                $trackcount++;
            }
        } 
    }
    close(FILE);
    
    if($trackcount > $tracklimit) {
        $trackcount = $tracklimit;
    }
    my $length = scalar @reportlines;
    my $firstline = $length - $trackcount;
    my $lastline = $length - 1;
    my $trackpos = 1;
    for (my $i = $firstline; $i <= $lastline; $i++) {
        my $reportrow = $reportlines[$i];
        $request->addResult("date_$trackpos", $reportrow->{date});
        $request->addResult("time_$trackpos", $reportrow->{time});
        $request->addResult("playerid_$trackpos", $reportrow->{playerid});
        $request->addResult("inputrate_$trackpos", $reportrow->{inputrate});
        $request->addResult("outputrate_$trackpos", $reportrow->{outputrate});
        $request->addResult("preamp_$trackpos", $reportrow->{preamp});
        $request->addResult("internalgain_$trackpos", $reportrow->{internalgain});  # <-- 2026/03/27
		$request->addResult("peakdBfs_$trackpos",     $reportrow->{peakdBfs});
		$request->addResult("inputpeak_$trackpos",    $reportrow->{inputpeak}); # <-- 2026/03/27
        $trackpos++;
    }

    $request->addResult("trackcount", $trackcount);
    $request->setStatusDone();
}

sub importwavCommand {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("importwavCommand ENTERED");

    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.importwav' ]])) {
        $request->setStatusBadDispatch();
        return;
    }

    my $filename = $request->getParam('_p0') || 'audio.wav';
    my $base64   = $request->getParam('_p1');
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Raw filename: " . $filename);

    unless ($base64) {
        $request->setStatusBadParams("Missing audio data");
        return;
    }

    # Security-focused sanitization
    # 1. Remove path components
    $filename =~ s/.*[\\\/]//g;
    
    # 2. Remove unsafe characters (keep alphanumeric, dots, dashes, underscores)
    $filename =~ s/[^\w\.\-]//g;
    
    # 3. Ensure we have a .wav extension
    $filename =~ s/\.wav$//i;
    $filename .= ".wav";
    
    # 4. Handle empty filename case
    $filename = "audio_import.wav" if $filename eq ".wav";
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Sanitized filename: $filename");
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Base64 length: " . length($base64));
    # Configure save path
    my $filepath = catfile($Plugins::SqueezeDSPNativeDSD::Plugin::pluginImpulsesDataDir, $filename);
 # Save file    
    if (open(my $fh, '>', $filepath)) {
        binmode $fh;
        print $fh decode_base64($base64);
        close $fh;
        Plugins::SqueezeDSPNativeDSD::Utils::debug("Saved WAV file: $filepath");
        $request->addResult('_success', 1);
        $request->setStatusDone();
    } else {
        Plugins::SqueezeDSPNativeDSD::Utils::debug("Save failed: $!");
        $request->setStatusBadParams("Couldn't write file: $!");
    }
}

sub saveallCommand {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Saving settings");
    
    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.saveall' ]])) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops($client, undef, "saveall not command");
        $request->setStatusBadDispatch();
        return;
    }

    my $json = $request->getParam('val') or return $request->setStatusBadParams("No data");
    my $data = eval { decode_json($json) };
    if ($@) {
        Plugins::SqueezeDSPNativeDSD::Utils::debug("JSON decode failed: $@");
        return $request->setStatusBadParams("Invalid JSON");
    }
    
    my $myJSONFile = Plugins::SqueezeDSPNativeDSD::Utils::getPrefFile($client);
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Saving settings to: $myJSONFile");
    Plugins::SqueezeDSPNativeDSD::Utils::debug("JSON length: " . length($json));
    Plugins::SqueezeDSPNativeDSD::Utils::SaveJSONFile($data, $myJSONFile);

    # Force DSP reload by seeking (if player available) - DO THIS BEFORE setStatusDone
    if ($client) {
        my $controller = $client->controller();
        if ($controller) {
            my $song = $controller->playingSong();
            if ($song) {
                my $current_track = $song->track();
                if ($current_track) {
                    # Define included protocols
                    my @included_protocols = qw(file http https smb nfs afp tidal spotify deezer qobuz hls);
                    # Define excluded file extensions
                    my @excluded_extensions = qw(wma wmal wmap);
                    # Get track URL
                    my $current_url = $current_track->url;
                    my $source = '';
                    my $extension = '';
                    # Extract protocol and extension
                    if ($current_url) {
                        ($source) = $current_url =~ m{^(\w+):};
                        $source = lc($source) if defined $source;
                        ($extension) = $current_url =~ /\.([a-z0-9]+)$/i;
                        $extension = lc($extension) if defined $extension;
                    }
                    
                    # Check if protocol is allowed
                    my $is_allowed_protocol = 0;
                    if ($source) {
                        $is_allowed_protocol = grep { $_ eq $source } @included_protocols;
                    }
                    
                    # Only proceed if allowed protocol and not excluded extension
                    if ($is_allowed_protocol && (!$extension || !grep { $_ eq $extension } @excluded_extensions)) {
                        # Get player state using controller methods
                        my $was_playing = $client->isPlaying();
                        my $current_position = $controller->playingSongElapsed();
                        my $track_duration = $controller->playingSongDuration();
                        
                        # Validate seek conditions
                        if ($was_playing && defined $current_position && defined $track_duration && $track_duration > 0) {
                            # Calculate new position (0.5s forward)
                            my $seek_amount = 0.5;
                            my $new_position = $current_position + $seek_amount;
                            
                            # Only seek if we're not at/near end of track
                            if ($new_position < $track_duration - 0.1) {
                                if ($was_playing) {
                                    $client->execute(['time', $new_position]);
                                } else {
                                    $client->execute(['pause', 0]);
                                    $client->execute(['time', $new_position]);
                                    $client->execute(['pause', 1]);
                                }
                                Plugins::SqueezeDSPNativeDSD::Utils::debug("DSP reload triggered: " . ($was_playing ? "Playing" : "Paused") . " track advanced to $new_position");
                            } else {
                                Plugins::SqueezeDSPNativeDSD::Utils::debug("Skipping seek near end of track (position: $current_position, duration: $track_duration sec)");
                            }
                        }
                    } else {
                        Plugins::SqueezeDSPNativeDSD::Utils::debug("Skipping seek for protocol: $source, extension: $extension");
                    }
                }
            }
        }
    }

    # NOW set the request as done - this sends the response to the client
    $request->addResult('_done', 1);
    $request->setStatusDone();
}
# Set a value for a specific key - contains some deprecated code
sub setvalCommand {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: setval");

    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.setval' ]])) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops($client, undef, "setval not command");
        $request->setStatusBadDispatch();
        return;
    }

    my $key = $request->getParam('key');
    if(!$key) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops($client, undef, "setval, no key!");
        $request->setStatusBadDispatch();
        return;
    }

    my $val = $request->getParam('val');
    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: setval($key,$val)");
    # Check this command is OK - not validating for now as it will fail anyway and too much change
    my $bandcount = Plugins::SqueezeDSPNativeDSD::Utils::getPref($client, 'EQBands');
    if($key eq 'EQBands') {
        Plugins::SqueezeDSPNativeDSD::Utils::setBandCount($client, $val);
        my $line = $client->string('PLUGIN_SQUEEZDSPNATIVEDSD_CHOSEN_BANDS');
        $client->showBriefly({ 'line' => [ undef, $line ], 'jive' => { 'type' => 'popupinfo', text => [ $line ] }, }, { 'duration' => 2 });
    } elsif($key eq 'FIRWavFile' || $key eq 'MatrixFile') {
        setFilterValue($client, $key, $val);
    } elsif($key eq 'Preset') {
        loadPresetFile($client, $val);
    } else {
        Plugins::SqueezeDSPNativeDSD::Utils::setPref($client, $key, $val);
        my $line = $client->string('PLUGIN_SQUEEZDSPNATIVEDSD_CHOSEN_VALUE');
        $client->showBriefly({ 'line' => [ undef, $line ], 'jive' => { 'type' => 'popupinfo', text => [ $line ] }, }, { 'duration' => 1 });
    }
    $request->setStatusDone();
}

sub setFilterValue {
    my ($client, $prf, $val) = @_;
    my $path;
    if($val eq '-' || $val eq '') {
        Plugins::SqueezeDSPNativeDSD::Utils::setPref($client, $prf, $val);
        my $msg = ($prf eq 'matrixfile') ? 'PLUGIN_SQUEEZDSPNATIVEDSD_CHOSEN_MATRIXFILTERNONE' : 'PLUGIN_SQUEEZDSPNATIVEDSD_CHOSEN_RCFILTERNONE';
        my $line = $client->string($msg);
        $client->showBriefly({ 'line' => [ undef, $line ], 'jive' => { 'type' => 'popupinfo', text => [ $line ] }, }, { 'duration' => 2 });
        return;
    }
    if($prf eq 'MatrixFile') {
        $path = catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginMatrixDataDir, $val);
    } else {
        $path = catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginImpulsesDataDir, $val);
    }
    if(-f $path) {
        Plugins::SqueezeDSPNativeDSD::Utils::setPref($client, $prf, $path);
        my $msg = ($prf eq 'matrixfile') ? 'PLUGIN_SQUEEZDSPNATIVEDSD_CHOSEN_MATRIXFILTER' : 'PLUGIN_SQUEEZDSPNATIVEDSD_CHOSEN_RCFILTER';
        my $line = $client->string($msg);
        $client->showBriefly({ 'line' => [ undef, $line ], 'jive' => { 'type' => 'popupinfo', text => [ $line ] }, }, { 'duration' => 2 });
    } else {
        Plugins::SqueezeDSPNativeDSD::Utils::debug("Can't set, file $path does not exist");
    }
}

sub saveasCommand {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: saveas");

    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.saveas' ]])) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops($client, undef, "saveas not command");
        $request->setStatusBadDispatch();
        return;
    }

    my $key = $request->getParam('preset');
    if(!$key) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops($client, undef, "saveas, no preset name!");
        $request->setStatusBadDispatch();
        return;
    }

    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: saveas($key)");


    my $file = catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginSettingsDataDir, join('_', split(/:/, $key)) . '.preset.json');
    Plugins::SqueezeDSPNativeDSD::Utils::setPref($client, 'Preset', $file);
    
    Plugins::SqueezeDSPNativeDSD::Utils::savePreset($client, $file);
        Plugins::SqueezeDSPNativeDSD::Utils::setPref($client, 'Last_preset', $key);
    my $line = $client->string('PLUGIN_SQUEEZDSPNATIVEDSD_PRESET_SAVED');
    $client->showBriefly({ 'line' => [ undef, $line ], 'jive' => { 'type' => 'popupinfo', text => [ $line ] }, }, { 'duration' => 2 });
    $request->setStatusDone();
}

sub readClientSettings {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("query: readClientSettings");
    my $myJSONFile = Plugins::SqueezeDSPNativeDSD::Utils::getPrefFile($client);
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Reading preset file: $myJSONFile");
    
    if (open(my $fh, '<', $myJSONFile)) {
        local $/;
        my $jsonContent = <$fh>;
        close $fh;
        $request->addResult('json', $jsonContent);
        $request->addResult('clientName', $client->name);
        $request->addResult('revision', $Plugins::SqueezeDSPNativeDSD::Plugin::revision);
        $request->setStatusDone();
    } else {
		# probably a new player
        Plugins::SqueezeDSPNativeDSD::Utils::debug("No settings file found for $myJSONFile - returning empty defaults");
        $request->addResult('json', '{}');
        $request->addResult('clientName', $client->name);
       	$request->addResult('revision', $Plugins::SqueezeDSPNativeDSD::Plugin::revision);
    	$request->addResult('fresh_player', 1);  # add this
        $request->setStatusDone();
    }
}


=pod
Amended to update client information to match current client
=cut
sub readPresetSettings {
    my $request = shift;
    my $client = $request->client();
    my $presetFileName = $request->getParam('presetFileName');
    Plugins::SqueezeDSPNativeDSD::Utils::debug("query: readPresetSettings");
    my $myJSONFile = Plugins::SqueezeDSPNativeDSD::Utils::getPrefFile($client);
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Copying preset: $presetFileName to $myJSONFile");
    
    unless (copy($presetFileName, $myJSONFile)) {
        my $error = "Copy failed: $presetFileName → $myJSONFile: $!";
        Plugins::SqueezeDSPNativeDSD::Utils::debug("ERROR: $error");
        $request->setStatusBadParams($error);
        return;
    }
    
    my $settings = {};
    if (open(my $fh, '<', $myJSONFile)) {
        local $/;
        my $jsonContent = <$fh>;
        close $fh;
        $settings = decode_json($jsonContent);
        # Extract just the preset name from the full path
        my $presetName = fileparse($presetFileName, qr/\.preset\.json$/);
        


        # Update client information to match current client
        $settings->{ClientName} = $client->name;
        $settings->{Client}->{Name} = $client->name;
        $settings->{Client}->{ID} = $client->id;
        $settings->{PresetName} = $presetName;
        # Write the updated settings back to the file
        if (open(my $fh_out, '>', $myJSONFile)) {
            my $updatedJsonContent = encode_json($settings);
            print $fh_out $updatedJsonContent;
            close $fh_out;
            
            $request->addResult('json', $updatedJsonContent);
            $request->addResult('clientName', $client->name);
            $request->addResult('revision', $Plugins::SqueezeDSPNativeDSD::Plugin::revision);
            $request->setStatusDone();
        } else {
            my $error = "Couldn't write updated settings to $myJSONFile: $!";
            Plugins::SqueezeDSPNativeDSD::Utils::debug("ERROR: $error");
            $request->setStatusBadParams($error);
        }
    } else {
        my $error = "Couldn't read $myJSONFile after copy: $!";
        Plugins::SqueezeDSPNativeDSD::Utils::debug("ERROR: $error");
        $request->setStatusBadParams($error);
    }
    return $settings;
}

sub getFiltersListNoNone {
    my ($client, $folder, $nopath) = @_;
    my %impulses = ();
    my $types = qr/\.(?:(wav))$/i;
    opendir(DIR, $folder) or do { return %impulses; };
    for my $item (readdir(DIR)) {
        my $itemPath = $item;
        my $fullPath = catdir($folder, $item);
        if(-f $fullPath) {
            if($item =~ $types) {
                $item =~ s/\.(?:(wav))$//i;
                $impulses{$nopath ? $itemPath : $fullPath} = $item;
            }
        }
    }
    closedir(DIR);
    return %impulses;
}

sub getFiltersList {
    my ($client, $folder, $nopath) = @_;
    my %impulses = ( '-' => $client->string('PLUGIN_SQUEEZDSPNATIVEDSD_FILTERNONE') );
    my %more = getFiltersListNoNone($client, $folder, $nopath);
    @impulses{keys %more} = values %more;
    return %impulses;
}

sub getPresetsListNoNone {
    my ($client, $nopath) = @_;
    my %presets = ();
    my $types = qr/\.(?:(preset\.json))$/i;
    if(opendir(DIR, $Plugins::SqueezeDSPNativeDSD::Plugin::pluginSettingsDataDir)) {
        for my $item (readdir(DIR)) {
            my $itemPath = $item;
            my $fullPath = catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginSettingsDataDir, $item);
            if(-f $fullPath) {
                if($item =~ $types) {
                    $item =~ s/\.(?:(preset\.json))$//i;
                    $presets{$nopath ? $itemPath : $fullPath} = $item;
                }
            }
        }
        closedir(DIR);
    }
    return %presets;
}

sub getPresetsList {
    my ($client, $nopath) = @_;
    my %presets = ( '-' => $client->string('PLUGIN_SQUEEZDSPNATIVEDSD_SAVEPRESETAS') );
    my %more = getPresetsListNoNone($client, $nopath);
    @presets{keys %more} = values %more;
    return %presets;
}

sub loadPresetFile {
    my ($client, $val) = @_;
    my $path = catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginSettingsDataDir, $val);
    if(-f $path) {
        Plugins::SqueezeDSPNativeDSD::Utils::loadPrefs($client, $path, undef);
    } else {
        Plugins::SqueezeDSPNativeDSD::Utils::debug("Can't set, file $path does not exist");
    }
}

sub deletepresetCommand {
    my $request = shift;
    my $client  = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: deletepreset");

    if ( $request->isNotQuery(
            [[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.deletepreset' ]] ) )
    {
        Plugins::SqueezeDSPNativeDSD::Utils::oops( $client, undef,
            "deletepreset not command" );
        $request->setStatusBadDispatch();
        return;
    }

    my $key = $request->getParam('preset');
    if ( !$key || $key eq '-' ) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops( $client, undef,
            "deletepreset: no preset name" );
        $request->setStatusBadDispatch();
        return;
    }

    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: deletepreset($key)");
	# sel_Preset values are already full paths; bare names need constructing
	my $file = ( $key =~ /\.preset\.json$/ )
		? $key
		: catdir(
			$Plugins::SqueezeDSPNativeDSD::Plugin::pluginSettingsDataDir,
			join( '_', split( /:/, $key ) ) . '.preset.json'
		);

    if ( !-f $file ) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops( $client, undef,
            "deletepreset: file not found: $file" );
        $request->setStatusBadDispatch();
        return;
    }

    unless ( unlink $file ) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops( $client, undef,
            "deletepreset: unlink failed: $!" );
        $request->setStatusBadDispatch();
        return;
    }

    # If deleted preset was the active one, clear both prefs
    my $lastPreset =
      Plugins::SqueezeDSPNativeDSD::Utils::getPref( $client, 'Last_preset' ) // '';
    if ( $lastPreset eq $key ) {
        Plugins::SqueezeDSPNativeDSD::Utils::setPref( $client, 'Last_preset', '' );
        Plugins::SqueezeDSPNativeDSD::Utils::setPref( $client, 'Preset',      '' );
    }

    my $line = $client->string('PLUGIN_SQUEEZDSPNATIVEDSD_PRESET_DELETED');
    $client->showBriefly(
        {
            'line' => [ undef, $line ],
            'jive' => { 'type' => 'popupinfo', text => [$line] },
        },
        { 'duration' => 2 }
    );

    $request->setStatusDone();
}


sub clearlogCommand {
    my $request = shift;
    my $client = $request->client();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("command: clearlog");

    if($request->isNotQuery([[ $Plugins::SqueezeDSPNativeDSD::Plugin::thistag . '.clearlog' ]])) {
        Plugins::SqueezeDSPNativeDSD::Utils::oops($client, undef, "clearlog not query");
        $request->setStatusBadDispatch();
        return;
    }

    my $logfile = $Plugins::SqueezeDSPNativeDSD::Plugin::logfile;
    
    # Check if log file exists and is writable
    if (! -e $logfile) {
        $request->addResult('_success', 0);
        $request->addResult('_message', 'Log file does not exist');
        $request->setStatusDone();
        return;
    }
    
    if (! -w $logfile) {
        $request->addResult('_success', 0);
        $request->addResult('_message', 'Log file is not writable');
        $request->setStatusDone();
        return;
    }
    
    # Try to clear the log file
    my $success = 0;
    my $message = '';
    
    eval {
        # Open in write mode to truncate (most efficient method)
        if (open(my $fh, '>', $logfile)) {
            # Optionally add a header/timestamp
            print $fh "# Log cleared at " . scalar(localtime) . "\n";
            close $fh;
            $success = 1;
            $message = 'Log cleared successfully';
            Plugins::SqueezeDSPNativeDSD::Utils::debug("Log file cleared: $logfile");
        } else {
            $message = "Could not open log file for writing: $!";
        }
    };
    
    if ($@) {
        $message = "Error clearing log: $@";
        Plugins::SqueezeDSPNativeDSD::Utils::debug("ERROR: $message");
    }
    
    $request->addResult('_success', $success);
    $request->addResult('_message', $message);
	
    $request->setStatusDone();
}

1;
