package HTML::Myasp;

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw/send_page/;

require 5.005_62;
use strict;
use warnings;

our $VERSION = '0.01';

use Carp;

my %CACHE;

sub send_page {

	local $SIG{__DIE__} = \&Carp::confess;

	my ($file, $hparam, $hreplace) = @_;

	my $tagprefix;

	my ($source, $string_text);
	if (length($file) > 128) {
		$source = 'string';
		$string_text = $file;
		$file = substr($file,0,255);
	} else {
		$source = 'file';
	}

	if (exists $ENV{MOD_PERL}) {
		my $r = Apache->request();
		$file = $r->document_root() . "/$file";
		$tagprefix = $r->dir_config("TagPrefix") || 'myasp';
	} else {
		$tagprefix = $ENV{TagPrefix} || 'myasp';
	}

	my $mtime = $source eq 'file' ? (stat($file))[9] : time;

	my ($package,$filename,$line) = caller;
	my $caller_mtime = (stat($filename))[9];

	if (!$CACHE{$file} || $mtime > $CACHE{$file}->{load_time} || $caller_mtime > $CACHE{$file}->{caller_mtime}) {

		if ($source eq 'file') {
			use IO::File;
			my $fh = new IO::File;
			$fh->open("<$file") or die "Couldn't open file $file. System error: $!";
			local $/ = undef;
			$CACHE{$file}->{f_text} = <$fh>;
			close $fh;
		} else {
			 $CACHE{$file}->{f_text} = $string_text;
		}

		$CACHE{$file}->{load_time} = time;
		$CACHE{$file}->{caller_mtime} = time;
			

		my ($last, @data);

		while ($CACHE{$file}->{f_text} =~ m#(.+?)<$tagprefix:(.+?)(\s.+?)?>(.*?)</$tagprefix:\2>#gs) {

			my %arr;
			if ($3) {
				my $aux = $3;
				$aux =~ s/^\s+//; $aux =~ s/\s+$//;
				%arr = split /=|\s+/, $aux;

				foreach (keys %arr) {
					$arr{$_} =~ s/"//g;
				}
			}
			push @data, {-html => $1, -type=>'html'};
			push @data, {-name=>"-$2", -coderef => $hparam->{"\-$2"}, -type=>'cod', -param_ref => \%arr, -param_body => $4} if $hparam->{"\-$2"};

			$last = $';
		
		}
		push @data, {-html => $last, -type=>'html'};
		$CACHE{$file}->{data} = \@data;
	}

	foreach my $x (@{$CACHE{$file}->{data}}) {
		if ($x->{-type} eq 'html') {
			my $temp = $x->{-html};
			foreach my $key (keys %$hreplace) {
				$temp =~ s/\b${key}\b/$hreplace->{$key}/gis;
			}
			print $temp;
		} else {
			&{$hparam->{$x->{-name}}}($x->{-param_ref}, $x->{-param_body});
		}
	
	}

	1;

}


1;
__END__

=head1 NAME

HTML::Myasp - Generate HTML pages based on Templates. JATP (Just Another
Template Parser).

=head1 SYNOPSIS

Create a Template myfile.html

 <html>
 ....
 __user__
 
 __date__
 
 
 <table>
 <tr><td>id</td><td>name</td></tr>
 <xx:users>
 <tr><td>dummy id 1</td><td>dummy name 1</td></tr>
 <tr><td>dummy id 2</td><td>dummy name 2</td></tr>
 </xx:users>
 ..
 <xx:other_data> ...</xx::other_data>
 
 </html>

The httpd.conf file.
 PerlSetVar TagPrefix xx
 <Files *.html>
 	SetHandler perl-script
 	PerlHandler MyModule
 </Files>

MyModule.pm
 use HTML::Myasp;
 
 package MyModule;

 ...

 sub handler {
 
 my $r = shift;
 $r->send_http_header("text/html");
 
 send_page('myfile.html', 
 {
 	-users => \&list_users,
 	-other_data => sub { print "this is the other data";  ... }
 }, 
 {
 	__user__ => $sesion->current_user,
 	__date__ => localtime(time),
 });

 ...
 
=head1 DESCRIPTION

This library is another template module for the generation of HTML pages. Why ?. Well primarily i wanted a module: light, that keeps mod_perl power and flow control like HTML::Template, good interaction with external contents administrators, have the chance of using naturally the print statement for generating web content, but, for some situations have the chance of directly replacing keywords in the template with local hash values.  In some way this module centralices the feature of a hash with values for replacing that you find in  HTML::Template and the XMLSubsMatch feature of Apache::ASP.

This module keeps the basic mod_perl flow, you control the flow, and permits the replacing with dynamic content, using two forms of marking. This modules is very well suited for working in parallell with the designes team, and leave each team advance in parallell. The flow of application keeps entirely in the handler.

We can say that this module dispatch the application in the call to send_page, and uses a callback style for tags replacing, and direct replacing of values capacity.

The module use a global CACHE hash, this avoids parsing files unless modified.

=head1 RECOMMENDED

 The recomended way to use this system is:
 Design the page with a graphic tool. 
 When designing consider:
 - Try to keep the maximum of design in the Template
 - Create the page as it will be in production, and surround big zones of dynamic html code with the tag methods. All the HTML in the zone is considered dummy, but can be used if the application wants.
 - Use keywords replacemente where you will provide an atomic value, like user name or date.

=head1 PARAMETERS

HTML::Myasp receives three parameters: filename, tags_hash, keywords_replace_hash

=head2 filename

This is the HTML file that acts as a template for the page that will be produced. The physical file is open and taken relative to the $r->document_root call (the Document Root).

=head2 tags_hash

The keys of this hash are the tags we put in the HTML file, the values correspond to a reference to subroutines that, for each key, will generate the content for everything between the initial and ending tag. In our Example:

The TagPrefix Parameter of httpd.conf is xx. 

In the HTML file we put the mark:

 <xx:users>
 <tr><td>dummy id 1</td><td>dummy name 1</td></tr>
 <tr><td>dummy id 2</td><td>dummy name 2</td></tr>
 </xx:users>
 
 In the call to send_page:
 send_page('myfile.html', 
 {
 	-users => \&list_users,
 	-other_data => sub { print "this is the other data";  ... }
 }, 
 {
 	__user__ => $sesion->current_user,
 	__date__ => localtime(time),
 });

The first key of the second parameter (the tags_hash) is "-users " and it points to a reference of a soubroutine. 

All this means this:

"All the content found in the template between the marks <xx:users> and </xx:users>, the marks inclusive, will be replaced with whatever the subroutine "list_users" prints, using the standard print command".

The second key "-other_data", is shown just to illustrate the declaration of an inline anonymous subroutine.

As in the module Apache::ASP, the subroutines will receive as the first parameter a hash reference with the attributes of the tag, and as a second argument the body of the tag. This may be useful in some cases when you want to use a micro template zone, for example, to predesign the rows in a table.

In the case of tables, is suggested to leave the table declaration in the template as in the example, and leave the rows marked, in order to be generate dynamically.

=head2 keywords_replace_hash

This parameter (optional), contains the keywords that will be replaced with the specified content. Note that no printing is allowed here, the value asigned to the keyword will be put in the resulting page. Each keyword will be replace as many times it appear in the document. 

Notice that no prefixing or sufixing is enforced here, the developer (or designer) can chose the keywords to replace at will.

This form is very well suited for the dynamic content asociated with aotmic values. As shown in the example:

The HTML file:

 <html>
 ....
 __user__
 __date__
 
 With the keywords_replace_hash
 ...
 {
 	__user__ => $sesion->current_user,
 	__date__ => localtime(time),
 });

Will render an HTML file with the result of calling $sesion->current_user instead of the string __user__. __date__ will be replaced with the result of calling localtime(time).

=head1 TODO

It uses a rude regex based parser i expect to polish it with something better in the future.

=head2 EXPORT

send_page

=head1 AUTHOR

Hans Poo, hans@opensource.cl

=head1 SEE ALSO

perl(1). Apache::ASP (XMLSubsMatch) HTML::Template

=cut

