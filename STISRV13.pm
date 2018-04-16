package STISRV13::Article;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('rss');
__PACKAGE__->add_columns(qw(rss_id author headline entete eng fra pubdate cible superstructure supertarget img imglink externallink alt view domain forward));

package STISRV13;

use base qw(DBIx::Class::Schema);

__PACKAGE__->load_classes(qw(Article));

sub connect {
  my ($class, %opts) = @_;
  my $dsn = ($opts{-dsn} or 'DBI:mysql:database=stisrv13;host=127.0.0.1;port=3307');
  my $username = ($opts{-dsn} or 'root');
  my $password = $opts{-password};
  return $class->SUPER::connect($dsn, $username, $password);
}

1;
