# 			ConfigManager::TemplateContentParser module
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package Plugins::SQLPlayList::ConfigManager::TemplateContentParser;

use strict;
use base 'Class::Data::Accessor';
use Plugins::SQLPlayList::ConfigManager::ContentParser;
our @ISA = qw(Plugins::SQLPlayList::ConfigManager::ContentParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use FindBin qw($Bin);

__PACKAGE__->mk_classaccessors( qw(templatePluginHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'playlist';
	my $self = $class->SUPER::new($parameters);
	$self->{'templatePluginHandler'} = $parameters->{'templatePluginHandler'};
	bless $self,$class;
	return $self;
}

sub loadTemplate {
	my $self = shift;
	my $client = shift;
	my $template = shift;
	my $parameters = shift;

	$self->debugCallback->("Searching for template: ".$template->{'id'}."\n");
	my $templateFileData = undef;
	my $doParsing = 1;
	if(defined($template->{lc($self->pluginId).'_plugin_template'})) {
		my $pluginTemplate = $template->{lc($self->pluginId).'_plugin_template'};
		if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
			$doParsing = 0;
		}
		$templateFileData = $self->templatePluginHandler->readDataFromPlugin($client,$template,$parameters);
	}else {
		my $templateFile = $template->{'id'};
		$templateFile =~ s/\.sql\.xml$/.sql.template/;
		my $templateDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_template_directory");
		my $path = undef;
		if (defined $templateDir && -d $templateDir && -e catfile($templateDir,$templateFile)) {
			$path = catfile($templateDir,$templateFile);
		}else {
			my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
			for my $plugindir (@pluginDirs) {
				if( -d catdir($plugindir,"SQLPlayList","Templates") && -e catfile($plugindir,"SQLPlayList","Templates",$templateFile)) {
					$path = catfile($plugindir,"SQLPlayList","Templates",$templateFile);
				}
			}
		}
		if(defined($path)) {
			$self->debugCallback->("Reading template: $templateFile\n");
			$templateFileData = eval { read_file($path) };
			if ($@) {
				$self->errorCallback->("Unable to open file: $path\nBecause of:\n$@\n");
			}else {
				my $encoding = Slim::Utils::Unicode::encodingFromString($templateFileData);
				if($encoding ne 'utf8') {
					$templateFileData = Slim::Utils::Unicode::latin1toUTF8($templateFileData);
					$templateFileData = Slim::Utils::Unicode::utf8on($templateFileData);
					$self->debugCallback->("Loading $templateFile and converting from latin1\n");
				}else {
					$templateFileData = Slim::Utils::Unicode::utf8decode($templateFileData,'utf8');
					$self->debugCallback->("Loading $templateFile without conversion with encoding ".$encoding."\n");
				}
			}
		}
	}
	if(!defined($templateFileData)) {
		return undef;
	}
	my %result = (
		'data' => \$templateFileData,
		'parse' => $doParsing
	);
	return \%result;
}

sub parse {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;
        $localcontext->{'simple'} = 1;
	return $self->parseTemplateContent($client,$item,$content,$items,$globalcontext->{'templates'},$globalcontext,$localcontext);
}

sub checkTemplateValues {
	my $self = shift;
	my $template = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	if(defined($template->{'downloadidentifier'})) {
		$localcontext->{'downloadidentifier'} = $template->{'downloadidentifier'};
	}
	return 1;
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
