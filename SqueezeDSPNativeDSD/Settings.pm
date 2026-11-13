package Plugins::SqueezeDSPNativeDSD::Settings;
# ----------------------------------------------------------------------------
# SqueezeDSP	\Settings.pm - player settings for SqueezeDSP plugin
# ----------------------------------------------------------------------------

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Plugins::SqueezeDSPNativeDSD::Plugin;

my $thistag = "squeezdspnativedsd";
my $thisapp = "SqueezeDSPNativeDSD";

my $log = logger('plugin.' . $thistag);
my $prefs = preferences('plugin.' . $thistag);
my $plugin;

sub new
{
	my $class = shift;
	$plugin   = shift;
	$class->SUPER::new;
}

sub name
{
    return 'PLUGIN_SQUEEZDSPNATIVEDSD_DISPLAYNAME';
}

sub needsClient
{
	return 1;
}

sub page
{
    return 'plugins/SqueezeDSPNativeDSD/settings/basic.html';
}


sub handler
{
	my ($class, $client, $params) = @_;
        return $class->SUPER::handler($client, $params);
}

$prefs->init({ "enabled" => 1, });

1;

__END__
