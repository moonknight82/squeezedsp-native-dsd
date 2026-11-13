package Plugins::SqueezeDSPNativeDSD::Configuration;
use strict;
use File::Spec::Functions qw(:ALL);
use Slim::Player::TranscodingHelper;
use Plugins::SqueezeDSPNativeDSD::Utils;
use Plugins::SqueezeDSPNativeDSD::TemplateConfig;
my %_initInProgress = ();
my $_conversionTablesClean = 0;

# ------ configuration helpers ------
sub initConfiguration {
    my $client = shift;
	#my $clientId = $client->id();
    Plugins::SqueezeDSPNativeDSD::Utils::debug( "client " . $client->id() ." name " . $client->name ." initializing" );

 	#return if $_initInProgress{$clientId};
    #$_initInProgress{$clientId} = 1;

	$Plugins::SqueezeDSPNativeDSD::Plugin::fatalError = undef;
    my $upgradeReason = '';
    my @origLines;
    my @clientIDs = sort map { $_->id() } Slim::Player::Client::clients();
    my @foundClients;

    @origLines = ();
    $Plugins::SqueezeDSPNativeDSD::Plugin::configPath = Plugins::SqueezeDSPNativeDSD::Utils::newConfigPath();
    sleep 1;
    Plugins::SqueezeDSPNativeDSD::Utils::debug ( "Config Path: " . $Plugins::SqueezeDSPNativeDSD::Plugin::configPath);

    if( -f $Plugins::SqueezeDSPNativeDSD::Plugin::configPath ) {
        open( CONFIG, "$Plugins::SqueezeDSPNativeDSD::Plugin::configPath" ) || do {
            Plugins::SqueezeDSPNativeDSD::Utils::fatal( $client, undef, "Can't read from $Plugins::SqueezeDSPNativeDSD::Plugin::configPath" );
            return 0;
        };
        @origLines = <CONFIG>;
        close( CONFIG );

        # Check for corruption: empty file or missing begin marker
        my $hasBeginMarker = grep( /#$Plugins::SqueezeDSPNativeDSD::Plugin::confBegin#rev:/i, @origLines );
        if( !@origLines || !$hasBeginMarker ) {
            Plugins::SqueezeDSPNativeDSD::Utils::debug( "Config file missing or corrupt, will rebuild fresh" );
            $upgradeReason = "Config file missing or corrupt" unless $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade;
            $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade = 1;
            @foundClients = @clientIDs;   # Include all current clients
            @origLines = ();              # Discard old contents
        } else {
            my @revs = split /\./, $Plugins::SqueezeDSPNativeDSD::Plugin::myconfigrevision;
            for( @origLines ) {
                if( m/#$Plugins::SqueezeDSPNativeDSD::Plugin::confBegin#rev\:(.*)#client\:(.*)#/i ) {
                    my @test = split /\./, $1;
                    for my $ver ( @revs ) {
                        my $vert = shift( @test ) || 0;
                        next if $vert == $ver;
                        Plugins::SqueezeDSPNativeDSD::Utils::debug ("Template version higher than config: " . $ver . " - " . $vert );
                        $upgradeReason = "Previous version $1 less than my $Plugins::SqueezeDSPNativeDSD::Plugin::myconfigrevision ($vert less than $ver)" unless $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade;
                        $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade = 1;
                        last;
                    }
                    push( @foundClients, $2 );
                }
            }
            unless( $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade ) {
                for my $c (@clientIDs) {
                    my $ok = 0;
                    for my $cc (@foundClients) {
                        if( $c eq $cc ) {
                            $ok = 1;
                            last;
                        }
                    }
                    unless( $ok ) {
                        $upgradeReason = "Client $c was not yet registered" unless $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade;
                        $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade = 1;
                        Plugins::SqueezeDSPNativeDSD::Utils::debug ("Client $c was not yet registered" );
                        push( @foundClients, $c );
                        last;
                    }
                }
            }
        }
    } else {
        Plugins::SqueezeDSPNativeDSD::Utils::debug ("Config Not found, new one created" );
        $upgradeReason = "New configuration" unless $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade;
        $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade = 1;
        @foundClients = @clientIDs;
    }

    upgradePrefs( @foundClients );
    removeNativeConversion();
    return unless $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade;

    Plugins::SqueezeDSPNativeDSD::Utils::debug( "Need to rewrite " . $Plugins::SqueezeDSPNativeDSD::Plugin::configPath . " (" .$upgradeReason . ")" );
    open( OUT, ">$Plugins::SqueezeDSPNativeDSD::Plugin::configPath" ) || do {
        Plugins::SqueezeDSPNativeDSD::Utils::fatal( $client, undef, "Can't write to $Plugins::SqueezeDSPNativeDSD::Plugin::configPath" );
        return;
    };

    my $now = localtime;
    print OUT "# Modified by $Plugins::SqueezeDSPNativeDSD::Plugin::thisapp, $now: $upgradeReason\n";
    foreach ( @origLines ) {
        print OUT if m/# Modified by $Plugins::SqueezeDSPNativeDSD::Plugin::thisapp/i;
    }
    print OUT "\n";

	foreach my $clientID ( @foundClients ) {
		print OUT "# #$Plugins::SqueezeDSPNativeDSD::Plugin::confBegin#rev:$Plugins::SqueezeDSPNativeDSD::Plugin::myconfigrevision#client:$clientID# ***** BEGIN AUTOMATICALLY GENERATED SECTION - DO NOT EDIT ****\n";
		
		my $client = Slim::Player::Client::getClient($clientID);
		my @formats;
		
		# Determine which formats to generate for this client
		if (defined($client) && 
			Slim::Player::Client::contentTypeSupported($client, 'flc') && 
			$client->model() ne "softsqueeze") {
			# Support both FLAC and MP3
			@formats = ('FLAC24', 'MP3');
		} else {
			# WAV and MP3 (fallback for non-FLAC clients or SoftSqueeze)
			@formats = ('WAV16','MP3');
		}
		
		# Generate and print a template for each format
		foreach my $fmt (@formats) {
			my $t = template($clientID, $fmt);
			print OUT $t;
			print OUT "\n";
		}
		
		print OUT "# #$Plugins::SqueezeDSPNativeDSD::Plugin::confEnd#client:$clientID# ***** END AUTOMATICALLY GENERATED SECTION - DO NOT EDIT *****\n";
		print OUT "\n";
	}

    close( OUT );

    # Verify that the file was written successfully and is non‑empty
    if( -s $Plugins::SqueezeDSPNativeDSD::Plugin::configPath == 0 ) {
        Plugins::SqueezeDSPNativeDSD::Utils::fatal( $client, undef, "Config file written but appears empty!" );
        return;
    }

    # Optionally set permissions so the file can be manually edited
    chmod 0666, $Plugins::SqueezeDSPNativeDSD::Plugin::configPath;   # or 0644 for owner‑only write

    $Plugins::SqueezeDSPNativeDSD::Plugin::needUpgrade = 0;
    Plugins::SqueezeDSPNativeDSD::Utils::debug( "Reload Conversion Tables" );
    Slim::Player::TranscodingHelper::loadConversionTables();
    removeNativeConversion();

}

sub removeUnwantedConversion {
    
    my $convolver = $Plugins::SqueezeDSPNativeDSD::Plugin::convolver;

    # Clear and reload for a clean, complete, duplicate-free table
    #%Slim::Player::TranscodingHelper::commandTable = ();
   # %Slim::Player::TranscodingHelper::capabilities = ();
    #Slim::Player::TranscodingHelper::loadConversionTables();

    # Now remove everything that isn't ours
    my $conv = Slim::Player::TranscodingHelper::Conversions();
    for my $profile (sort keys %$conv) {
        my $command = $conv->{$profile};
        if (index($command, $convolver) == -1) {
            Plugins::SqueezeDSPNativeDSD::Utils::debug("delete unwanted entry: $profile => $command");
            delete $Slim::Player::TranscodingHelper::commandTable{$profile};
            delete $Slim::Player::TranscodingHelper::capabilities{$profile};
        }
    }
    Plugins::SqueezeDSPNativeDSD::Utils::debug("removeNativeConversion complete.");
}

sub removeNativeConversion {
  my $conv = Slim::Player::TranscodingHelper::Conversions();
    my %players = %{Plugins::SqueezeDSPNativeDSD::Utils::_getEnabledPlayers()};
    my $convolver = $Plugins::SqueezeDSPNativeDSD::Plugin::convolver;

    # Fallback to 'SqueezeDSP' in case $convolver is unexpectedly empty
    my $conv_placeholder = '[' . ($convolver || 'SqueezeDSP') . ']';

    for my $profile (sort keys %$conv) {
        my ($inputtype, $outputtype, $clienttype, $clientid) = Plugins::SqueezeDSPNativeDSD::Utils::_inspectProfile($profile);
        my $command = $conv->{$profile};
        my $enabled = Slim::Player::TranscodingHelper::enabledFormat($profile);
        my %SUPPORTED_NATIVE_INPUTS = map { $_ => 1 } qw(aac aif alc alcx ape dsf dff flc hls mov mp3 mp4 mp4x mpc ogg ogf ops spt wav wma wmal wmap wvp);

        if ($SUPPORTED_NATIVE_INPUTS{$inputtype}) {
            # Keep only commands that use our own convolver (by matching the placeholder)
            # Use \Q...\E to safely handle any special regex characters
            next if $command =~ /\Q$conv_placeholder\E/;

            # Keep native DSD passthrough. SqueezeDSP can process PCM, but
            # deleting these profiles forces DSF/DFF through a PCM conversion.
            if ($command eq "-" && $inputtype eq $outputtype
                && ($inputtype eq "dsf" || $inputtype eq "dff")) {
                next;
            }

            # Remove native (direct) entries
            if ($enabled == 1 && $command eq "-") {
                Plugins::SqueezeDSPNativeDSD::Utils::debug("delete native command - input: $inputtype, output $outputtype, clienttype $clienttype, clientid $clientid, enabled $enabled, command $command");
                delete $Slim::Player::TranscodingHelper::commandTable{ $profile };
                delete $Slim::Player::TranscodingHelper::capabilities{ $profile };
            }
            # Remove competing conversions to flac or mp3 (not our own)
            elsif ($enabled == 1 && ($outputtype eq "flc" || $outputtype eq "mp3" || $outputtype eq "wav")) {
                Plugins::SqueezeDSPNativeDSD::Utils::debug("delete $outputtype command - input: $inputtype, output $outputtype, clienttype $clienttype, clientid $clientid, enabled $enabled, command $command");
                delete $Slim::Player::TranscodingHelper::commandTable{ $profile };
                delete $Slim::Player::TranscodingHelper::capabilities{ $profile };
            }
        } else {
            Plugins::SqueezeDSPNativeDSD::Utils::debug("skip profile $profile - input $inputtype not in supported list or is a direct-stream sentinel");
        }
    }
}


# Going to run this each time the server starts and update revision number for each active client
sub upgradePrefs
{
	# Going to run this each time the server starts and update revision number for each active client
	# 
	my (  @clientIDs ) = @_;
	$Plugins::SqueezeDSPNativeDSD::Plugin::revision;
		
	foreach my $clientID ( @clientIDs )
	{
		Plugins::SqueezeDSPNativeDSD::Utils::debug( "client " . $clientID );
		my $client = Slim::Player::Client::getClient( $clientID );
	# Check IMMEDIATELY after getClient()
    unless (defined($client)) 
		{  # Or if (not defined $client) {
        print "Error: Could not get client object for ID: " . $clientID;
        next; # Skip to the next client ID
    	}	
		# Check the current and previous installed versions of the plugin,
		# in case we need to upgrade the prefs store (for this client)
		
		my $myJSONFile = Plugins::SqueezeDSPNativeDSD::Utils::getPrefFile( $client );
		
		unless( -f $myJSONFile )
		{
			#create default file if it does not exist
			Plugins::SqueezeDSPNativeDSD::Utils::debug( $client,  "Player Config File $myJSONFile not found. Creating" );
			#need to create file first
			my $myDefault = my $myDefault = {
				Client     => { Bypass => "1" },
				ClientName => "",
				Revision   => 0
			};
			Plugins::SqueezeDSPNativeDSD::Utils::SaveJSONFile ($myDefault, $myJSONFile );
			#Plugins::SqueezeDSPNativeDSD::Utils::defaultPrefs( $client );
		}

		my $myConfig = Plugins::SqueezeDSPNativeDSD::Utils::LoadJSONFile ($myJSONFile);
		Plugins::SqueezeDSPNativeDSD::Utils::debug ( $clientID . " Config File " . $myJSONFile . " loaded" );
		my $prevrev = $myConfig->{Client}->{Version};
	
		#Now touch the version numbers	
		if( defined( $client ) )
		{
			if ( $prevrev eq $Plugins::SqueezeDSPNativeDSD::Plugin::revision )
			{
				Plugins::SqueezeDSPNativeDSD::Utils::debug ( "upgrade from " . $prevrev . " not required " )	;
			}
		
			else   
			{
				Plugins::SqueezeDSPNativeDSD::Utils::debug( "upgrade from " . $prevrev . " to " . $Plugins::SqueezeDSPNativeDSD::Plugin::revision );
				Plugins::SqueezeDSPNativeDSD::Utils::setPref( $client, "Version", $Plugins::SqueezeDSPNativeDSD::Plugin::revision );
			
			}
		}
	}
}


# find the appropriate template depending on client type
sub template {
    my ($clientID, $format) = @_;
    my $client = Slim::Player::Client::getClient($clientID);
    my $template;
    
    # Choose the template based on the requested format
    if ($format eq 'FLAC24') {
        $template = Plugins::SqueezeDSPNativeDSD::TemplateConfig::template_FLAC24();
    } elsif ($format eq 'MP3') {
        $template = Plugins::SqueezeDSPNativeDSD::TemplateConfig::template_MP3();
    } else {
        # fallback (should not happen)
        $template = Plugins::SqueezeDSPNativeDSD::TemplateConfig::template_MP3();
    }
    
    # Substitute placeholders (same as before)
    my $pipeout;
    my $pipenul;
    if (Slim::Utils::OSDetect::OS() eq 'win') {
        $pipeout = '#PIPE#';
        $pipenul = '';
    } else {
        $pipeout = '/dev/fd/4';
        $pipenul = '4>&1 1>/dev/null';
    }
    
    $template =~ s/\$CONVAPP\$/$Plugins::SqueezeDSPNativeDSD::Plugin::convolver/g;
    $template =~ s/\$CLIENTID\$/$clientID/g;
    $template =~ s/\$PIPEOUT\$/$pipeout/g;
    $template =~ s/\$PIPENUL\$/$pipenul/g;
    
    return $template;
}

1;
