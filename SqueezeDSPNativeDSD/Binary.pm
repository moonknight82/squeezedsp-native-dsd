package Plugins::SqueezeDSPNativeDSD::Binary;
use strict;
use File::Copy;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Network;
use Slim::Utils::Prefs;
#use Plugins::SqueezeDSPNativeDSD::Plugin qw($log $thisapp $pluginDataDir $pluginSettingsDataDir $pluginImpulsesDataDir $pluginMatrixDataDir $pluginTempDataDir);

sub binaries {
    my $os = Slim::Utils::OSDetect::details();
    if ($os->{'os'} eq 'Linux') {
        if ($os->{'osArch'} =~ /x86_64/) {
            return qw(/publishLinux-x64/SqueezeDSP);
        }
        if ($os->{'binArch'} =~ /i386/) {
            return qw(/publishLinux-x86/SqueezeDSP);
        }
        if ($os->{'osArch'} =~ /aarch64/) {
            return qw(/publishlinux-arm64/SqueezeDSP);
        }
        if ($os->{'binArch'} =~ /armhf/) {
            return qw(/publishlinux-arm/SqueezeDSP);
        }
        if ($os->{'binArch'} =~ /arm/) {
            return qw(/publishlinux-arm/SqueezeDSP);
        }
        return qw(/publishLinux-x86/SqueezeDSP);
    }
    if ($os->{'os'} eq 'Unix') {
        if ($os->{'osName'} =~ /freebsd/) {
            return qw(/publishLinux-x64/SqueezeDSP);
        }
    }
    if ($os->{'os'} eq 'Darwin') {
        if ($os->{'osArch'} =~ /arm64/) {
            return qw(/publishOSX-arm64/SqueezeDSP);
        }
        return qw(/publishOSX-x64/SqueezeDSP);
    }
    if ($os->{'os'} eq 'Windows') {
        return qw(\publishWin64\SqueezeDSP.exe);
    }
}

sub setup_binary {
    my $class = shift;
    #my $bin = $class->binaries();
    my $bin = binaries();
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Fox plugin path: " . $bin . " binary");
    my $exec = catdir(Slim::Utils::PluginManager->allPlugins->{$Plugins::SqueezeDSPNativeDSD::Plugin::thisapp}->{'basedir'}, 'Bin', $bin);
    Plugins::SqueezeDSPNativeDSD::Utils::debug("Fox plugin path: " . $exec . " exec");
    my $binExtension = ".exe";
    if (Slim::Utils::OSDetect::details()->{'os'} ne 'Windows') {
        $binExtension = "";
        chmod(0777, $Plugins::SqueezeDSPNativeDSD::Plugin::pluginImpulsesDataDir);
        chmod(0777, $Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir);
    }
    if (!-e $exec) {
        $Plugins::SqueezeDSPNativeDSD::Plugin::log->warn("$exec not executable");
    }
    my $binpath = catdir(Slim::Utils::PluginManager->allPlugins->{$Plugins::SqueezeDSPNativeDSD::Plugin::thisapp}->{'basedir'}, 'Bin', "/", $Plugins::SqueezeDSPNativeDSD::Plugin::convolver . $binExtension);
    my $binversion_path = catdir(Slim::Utils::PluginManager->allPlugins->{$Plugins::SqueezeDSPNativeDSD::Plugin::thisapp}->{'basedir'}, 'Bin', "/", $Plugins::SqueezeDSPNativeDSD::Plugin::binversion);
    Plugins::SqueezeDSPNativeDSD::Utils::debug('standard binary path: ' . $binpath);
    if (-e $binversion_path) {
        Plugins::SqueezeDSPNativeDSD::Utils::debug('copying binary' . $exec);
        copy($exec, $binpath) or die "copy failed: $!";
        if ($binExtension eq "") {
            Plugins::SqueezeDSPNativeDSD::Utils::debug('executable not having \'x\' permission, correcting');
            chmod(0555, $binpath);
        }
        unlink $binversion_path;
        housekeeping();
    }
    my $appConfig = catdir(Slim::Utils::PluginManager->allPlugins->{$Plugins::SqueezeDSPNativeDSD::Plugin::thisapp}->{'basedir'}, 'Bin', "/", 'SqueezeDSP_config.json');
    amendPluginConfig($appConfig, 'pluginDataFolder', $Plugins::SqueezeDSPNativeDSD::Plugin::pluginDataDir);
    amendPluginConfig($appConfig, 'settingsDataFolder', $Plugins::SqueezeDSPNativeDSD::Plugin::pluginSettingsDataDir);
    amendPluginConfig($appConfig, 'impulseDataFolder', $Plugins::SqueezeDSPNativeDSD::Plugin::pluginImpulsesDataDir);
    amendPluginConfig($appConfig, 'tempDataFolder', $Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir);
    my $mybinary = Slim::Utils::Misc::findbin('sox');
    amendPluginConfig($appConfig, 'soxExe', $mybinary);
	my $mybinary = Slim::Utils::Misc::findbin('ffmpeg');
    amendPluginConfig($appConfig, 'ffmpegExe', $mybinary);
		my $mybinary = Slim::Utils::Misc::findbin('lame');
    amendPluginConfig($appConfig, 'lameExe', $mybinary);



    $Plugins::SqueezeDSPNativeDSD::Plugin::logfile = catdir(Slim::Utils::OSDetect::dirsFor('log'), "squeezdspnativedsd.log");
    if (! -e $Plugins::SqueezeDSPNativeDSD::Plugin::logfile) {
        open my $fh, '>', $Plugins::SqueezeDSPNativeDSD::Plugin::logfile or die "Could not create log file: $!";
        close $fh;
        Plugins::SqueezeDSPNativeDSD::Utils::debug('Log file created: ' . $Plugins::SqueezeDSPNativeDSD::Plugin::logfile);
    } else {
        Plugins::SqueezeDSPNativeDSD::Utils::debug('Log file already exists: ' . $Plugins::SqueezeDSPNativeDSD::Plugin::logfile);
    }
    amendPluginConfig($appConfig, 'logFile', $Plugins::SqueezeDSPNativeDSD::Plugin::logfile);
	# add LMS host and port to config for use by binary when calling back to server
	my $lmsHost = Slim::Utils::Network::serverAddr();
	my $serverPrefs = preferences('server');
	my $lmsPort = $serverPrefs->get('httpport') || 9000;
	amendPluginConfig($appConfig, 'lmsHost', $lmsHost);
	amendPluginConfig($appConfig, 'lmsPort', $lmsPort);
}

sub housekeeping {
    unlink glob catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir, "/", '*.filter');
    unlink glob catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir, "/", '*.filter.wav');
    unlink glob catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir, "/", '*.wav');
	unlink glob catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir, "/", '*.gob');
    unlink grep { !/\current.json/ } glob catdir($Plugins::SqueezeDSPNativeDSD::Plugin::pluginTempDataDir, "/", '*.json');
}

sub amendPluginConfig {
    my ($myJSONFile, $myKey, $myValue) = @_;
    Plugins::SqueezeDSPNativeDSD::Utils::debug('Fox amend file: ' . $myJSONFile . ' for key =' . $myKey . ' value= ' . $myValue);
    my $myConfig =  Plugins::SqueezeDSPNativeDSD::Utils::LoadJSONFile($myJSONFile);
    $myConfig->{settings}->{$myKey} = $myValue;
    Plugins::SqueezeDSPNativeDSD::Utils::SaveJSONFile($myConfig, $myJSONFile);
}

1;