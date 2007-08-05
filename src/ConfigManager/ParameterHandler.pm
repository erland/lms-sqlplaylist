# 			ConfigManager::ParameterHandler module
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

package Plugins::SQLPlayList::ConfigManager::ParameterHandler;

use strict;

use base 'Class::Data::Accessor';

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use DBI qw(:sql_types);
use HTML::Entities;

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback parameterPrefix criticalErrorCallback) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'parameterPrefix' => $parameters->{'parameterPrefix'},
		'criticalErrorCallback' => $parameters->{'criticalErrorCallback'},
	};
	bless $self,$class;
	return $self;
}

sub quoteValue {
	my $value = shift;
	$value =~ s/\'/\\\'/g;
	$value =~ s/\"/\\\"/g;
	$value =~ s/\\/\\\\/g;
	return $value;
}

sub addValuesToTemplateParameter {
	my $self = shift;
	my $p = shift;
	my $currentValues = shift;

	if($p->{'type'} =~ '^sql.*') {
		my $listValues = $self->getSQLTemplateData($p->{'data'});
		if($p->{'type'} =~ /.*optional.*/) {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @$listValues,\%empty;
		}
		$p->{'values'} = $listValues;
	}elsif($p->{'type'} =~ 'function.*') {
		my $listValues = $self->getFunctionTemplateData($p->{'data'});
		if($p->{'type'} =~ /.*optional.*list$/) {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @$listValues,\%empty;
		}
		if($p->{'value'}) {
			for my $v (@$listValues) {
				$v->{'selected'} = 1;
			}
		}
		$p->{'values'} = $listValues;
	}elsif($p->{'type'} =~ '.*list$' || $p->{'type'} =~ '.*checkboxes$') {
		my @listValues = ();
		my @values = split(/,/,$p->{'data'});
		for my $value (@values){
			my @idName = split(/=/,$value);
			my %listValue = (
				'id' => @idName->[0],
				'name' => @idName->[1]
			);
			if(scalar(@idName)>2) {
				$listValue{'value'} = @idName->[2];
			}else {
				$listValue{'value'} = @idName->[0];
			}
			push @listValues, \%listValue;
		}
		if($p->{'type'} =~ /.*optional.*list$/) {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @listValues,\%empty;
		}
		$p->{'values'} = \@listValues;
	}
	if(defined($currentValues)) {
		$self->setValueOfTemplateParameter($p,$currentValues);
	}
}

sub setValueOfTemplateParameter {
	my $self = shift;
	my $p = shift;
	my $currentValues = shift;

	if(defined($currentValues)) {
		if($p->{'type'} =~ '^sql.*' || $p->{'type'} =~ 'function.*' || $p->{'type'} =~ '.*list$' || $p->{'type'} =~ '.*checkboxes$') {
			my $listValues = $p->{'values'};
			for my $v (@$listValues) {
				if($currentValues->{$v->{'value'}}) {
					$v->{'selected'} = 1;
				}else {
					$v->{'selected'} = undef;
				}
			}
		}else {
			for my $v (keys %$currentValues) {
				$p->{'value'} = $v;
			}
		}
	}
}

sub getValueOfTemplateParameter {
	my $self = shift;
	my $params = shift;
	my $parameter = shift;

	my $result = undef;
	my $dbh = getCurrentDBH();
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = $self->getMultipleListQueryParameter($params,$self->parameterPrefix.'_'.$parameter->{'id'});
		}else {
			$selectedValues = $self->getCheckBoxesQueryParameter($params,$self->parameterPrefix.'_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				if(defined($result)) {
					$result = $result.',';
				}
				my $thisvalue = quoteValue($item->{'value'});
				if($parameter->{'quotevalue'}) {
					$result .= "'".encode_entities($thisvalue,"&<>\'\"")."'";
				}else {
					$result .= encode_entities($thisvalue,"&<>\'\"");
				}
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
		$selectedValue = Slim::Utils::Unicode::utf8decode_locale($selectedValue);
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				my $thisvalue = quoteValue($item->{'value'});
				if($parameter->{'quotevalue'}) {
					$result = "'".encode_entities($thisvalue,"&<>\'\"")."'";
				}else {
					$result = encode_entities($thisvalue,"&<>\'\"");
				}
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}else{
		if($params->{$self->parameterPrefix.'_'.$parameter->{'id'}}) {
			my $thisvalue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
			$thisvalue = quoteValue(Slim::Utils::Unicode::utf8decode_locale($thisvalue));
			if($parameter->{'quotevalue'}) {
				return "'".encode_entities($thisvalue,"&<>\'\"").".";
			}else {
				return encode_entities($thisvalue,"&<>\'\"");
			}
		}else {
			if($parameter->{'type'} =~ /.*checkbox$/) {
				$result = '0';
			}else {
				$result = '';
			}
		}
	}
	return $result;
}


sub getXMLValueOfTemplateParameter {
	my $self = shift;
	my $params = shift;
	my $parameter = shift;

	my $dbh = getCurrentDBH();
	my $result = undef;
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = $self->getMultipleListQueryParameter($params,$self->parameterPrefix.'_'.$parameter->{'id'});
		}else {
			$selectedValues = $self->getCheckBoxesQueryParameter($params,$self->parameterPrefix.'_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				$result = $result.'<value>';
				$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				$result = $result.'</value>';
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
		$selectedValue = Slim::Utils::Unicode::utf8decode_locale($selectedValue);
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				$result = $result.'<value>';
				$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				$result = $result.'</value>';
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}else{
		if(defined($params->{$self->parameterPrefix.'_'.$parameter->{'id'}}) && $params->{$self->parameterPrefix.'_'.$parameter->{'id'}} ne '') {
			my $value = Slim::Utils::Unicode::utf8decode_locale($params->{$self->parameterPrefix.'_'.$parameter->{'id'}});
			$result = '<value>'.encode_entities($value,"&<>\'\"").'</value>';
		}else {
			if($parameter->{'type'} =~ /.*checkbox$/) {
				$result = '<value>0</value>';
			}else {
				$result = '';
			}
		}
	}
	return $result;
}

sub getMultipleListQueryParameter {
	my $self = shift;
	my $params = shift;
	my $parameter = shift;

	my $query = $params->{url_query};
	my %result = ();
	if($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /([^=]+)=(.*)/) {
				my $name  = unescape($1);
				my $value = unescape($2);
				if($name eq $parameter) {
					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '') {
						$value = Slim::Utils::Unicode::utf8on($value);
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}
					$result{$value} = 1;
				}
			}
		}
	}
	return \%result;
}

sub getCheckBoxesQueryParameter {
	my $self = shift;
	my $params = shift;
	my $parameter = shift;

	my %result = ();
	foreach my $key (keys %$params) {
		my $pattern = '^'.$parameter.'_(.*)';
		if ($key =~ /$pattern/) {
			my $id  = unescape($1);
			if ($id ne '*' && $id ne '') {
				$id = Slim::Utils::Unicode::utf8on($id);
				$id = Slim::Utils::Unicode::utf8encode_locale($id);
			}
			$result{$id} = 1;
		}
	}
	return \%result;
}

sub getSQLTemplateData {
	my $self = shift;
	my $sqlstatements = shift;
	my @result =();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
    	for my $sql (split(/[;]/,$sqlstatements)) {
	    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$self->debugCallback->("Executing: $sql\n");
			$sth->execute() or do {
				$self->debugCallback->("Error executing: $sql\n");
				$sql = undef;
			};
	
			if ($sql =~ /^SELECT+/oi) {
				$self->debugCallback->("Executing and collecting: $sql\n");
				my $id;
				my $name;
				my $value;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				$sth->bind_col( 3, \$value);
				while( $sth->fetch() ) {
					my %item = (
						'id' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($id,'utf8')),
						'name' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($name,'utf8')),
						'value' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($value,'utf8'))
					);
					push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			warn "Database error: $DBI::errstr\n";
			$self->criticalErrorCallback->("Running: $sql got error: <br>".$DBI::errstr);
		}		
	}
	return \@result;
}

sub getFunctionTemplateData {
	my $self = shift;
	my $data = shift;
    	my @params = split(/\,/,$data);
	my @result =();
	if(scalar(@params)==2) {
		my $object = @params->[0];
		my $function = @params->[1];
		if(UNIVERSAL::can($object,$function)) {
			$self->debugCallback->("Getting values for: $function\n");
			no strict 'refs';
			my $items = eval { &{$object.'::'.$function}() };
			if( $@ ) {
			    warn "Function call error: $@\n";
			}		
			use strict 'refs';
			if(defined($items)) {
				@result = @$items;
			}
		}
	}else {
		$self->debugCallback->("Error getting values for: $data, incorrect number of parameters ".scalar(@params)."\n");
	}
	return \@result;
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}
1;

__END__
