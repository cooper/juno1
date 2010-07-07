#!/usr/bin/perl
print "Password: ";
$password = <>;
$hash = crypt(trim($password),"pb");
print "Hashed password for ".trim($password)." is\n";
print "$hash\n";

sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
