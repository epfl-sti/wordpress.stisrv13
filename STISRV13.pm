package STISRV13::DatabaseRow;

use strict;

use base qw/DBIx::Class::Core/;

# http://search.cpan.org/~blblack/DBIx-Class-0.07006/lib/DBIx/Class/Manual/Cookbook.pod#Debugging_DBIx::Class_objects_with_Data::Dumper
sub _dumper_hook {
  $_[0] = bless {
    %{ $_[0] },
    result_source => undef,
  }, ref($_[0]);
}

package STISRV13::Article;

use STISRV13::Date;

use base qw(STISRV13::DatabaseRow);

use Debug::Statements;
# Debug::Statements::setFlag('$STISRV13::Article::d'); our $d = 1;

use String::Similarity qw(similarity);
use Lingua::Identify qw(langof);

use constant MIN_BODY_SIZE => 10;

__PACKAGE__->table('rss');
__PACKAGE__->add_columns(qw(rss_id author headline entete eng fra pubdate cible superstructure supertarget img imglink externallink alt view domain forward));

sub almost_all {
  my ($class, $schema) = @_;
  return $schema->resultset('Article')->search({-and => [
    # As per ssh://stisv13/home/websti/public_html/cgi-bin/newnews.pl,
    # IDs <= 19 are tests.
    {rss_id => {">=" => 20}},
    [
      \("LENGTH(eng) >= " . MIN_BODY_SIZE),
      \("LENGTH(fra) >= " . MIN_BODY_SIZE),
    ]
  ]});
}

sub pubdate_datetime {
  my ($self) = @_;
  my $pubdate_txt = $self->pubdate;
  return STISRV13::Date->parse($pubdate_txt);
}

sub pubdate_epoch {
  my ($self) = @_;
  return unless (my $pubdate = $self->pubdate_datetime());
  return scalar $pubdate->epoch;
}

sub webmaster_author {
  my $self = shift;
  local $_ = $self->author;

  # STI staff
  m/Dietrich|Reinhard/              && return "dreinhar";
  m/\wUtz\w/                        && return "dutz";
  m/^(?:PGB|Philippe)/              && return "pgaybalm";
  m/Gay.Balmaz/                     && return "pgaybalm";
  m/Homeira/                        && return "sunderla";
  m/^Ingrid/                        && return "ifischer";
  m/^John/                          && return "maxwell";
  m/^Isabelle/                      && return "imorel";  # Isabelle Schafer
  m/^L\W+A\b/                       && return "pessina";
  m/^(Laure-Anne|Anne-Laure|Lara)/i && return "pessina";
  m/^(Pessina)/i                    && return "pessina";
  m/^(nbo|Nicolas)/i                && return "nborboen";

  # Mediacom
  m/Barraud/       && return "ebarraud";
  m/^Corinn?e/     && return "cfeuz";
  m/\wRauss\w/     && return "rauss";
  m/^Sandy\w/      && return "cmundwil";  # Santy Evangelista
  m/^Sarah Perrin/ && return "sperrin";
  m/Sanctuary|^Hillary$/ && return "hsanctua";
  m/^Nik\b/i             && return "npapageo";  # Nik Papageorgiou
  m/Patrick Mayor/       && return 111483;

  # Research Office
  m/Patricia Marti-Rochat/ && return "pamarti";

  # Other
  m/Patrick Mayor/       && return "pmayor";    # Scientific writer @ NANO-TERA

  return;
}


sub academic_author {
  my $self = shift;
  local $_ = $self->author;

  m|/| && return; m|,| && return;  # Co-authors not handled (yet)

  m/^Aude Billard$/      && return 115671;
  m/^Auke Ijspeert/      && return 115955;
  m/Vandevyver/          && return 138412;
  m/^Dario/              && return 258955;
  m/Van De Ville/i       && return 152027;
  m/Farhad/              && return 106170;
  m/Bleuler/             && return 104561;
  m/^Nanni$/             && return 167918;  # Giovanni de Micheli
  m/^Nanolab/i           && return 122431;  # Mihut Ionescu
  m/\wpv-lab\w/i         && return 100192;  # Christophe Ballif
  m/Samuel Zimmermann/   && return 244428;

  return;
}

sub in_the_media_author {
  my $self = shift;
  local $_ = $self->author;

  m/\w(BBC|CNN)\w/ && return $1;

  return;
}

sub corp_author {
  my $self = shift;
  local $_ = $self->author;

  m/\w(EMC)\w/       && return "EMC";
  m/\w(Leclanché)\w/ && return "Leclanché";
  m/Marcel Benoist/  && return "Marcel Benoist Foundation";

  return;
}

sub languages {
  my ($self) = @_;

  my @langs = grep {length($self->body($_)) >= MIN_BODY_SIZE} (qw(en fr));
  return @langs unless (scalar(@langs) == 2);

  my $rss_id = $self->rss_id;
  my ($body_en, $body_fr) = map { scalar $self->body($_) } qw(en fr);
  if (similarity($body_en, $body_fr) > 0.98) {
    my $guessed = langof($body_en);
    if ($guessed eq 'en') {
      return qw(en);
    } elsif ($guessed eq 'fr') {
      d q($rss_id appears to be written in French);
      return qw(fr);
    } else {
      d q($rss_id appears to be written in a weird language);
      d q($guessed is the language);
      return qw(en);   # ¯\_(ツ)_/¯
    }
  }
  return @langs;
}

sub body {
  my ($self, $lang) = @_;
  return ($lang eq "en" ? $self->eng : $self->fra);
}

sub essentials {
  my ($self, $lang) = @_;
  die "Bad \$lang: $lang" unless $lang =~ m/^(en|fr)$/i;

  my %retval = (
    lang                => $lang,
    rss_id              => $self->rss_id,
    title               => $lang eq "en" ? $self->headline : $self->entete,
    body                => $self->body($lang),
    academic_author     => scalar $self->academic_author,
    webmaster_author    => scalar $self->webmaster_author,
    in_the_media_author => scalar $self->in_the_media_author,
    corp_author         => scalar $self->corp_author,
    pubdate             => scalar $self->pubdate_epoch,
    covershot_alt       => scalar $self->alt
   );
  if ($retval{title} !~ m/\S/) {
    delete $retval{title};
  }
  foreach my $k (keys(%retval)) {
    delete $retval{$k} unless defined $retval{$k};
  }
  return \%retval;
}

package STISRV13::ProfVideo;

use base qw(STISRV13::DatabaseRow);

__PACKAGE__->table('profs');
__PACKAGE__->add_columns(qw(videoeng videofra videotext videotextfr videotitle videotitlefr videoLH epflname firstname surname));
__PACKAGE__->add_columns(sciper => { accessor => '_sciper' });  # Overridden below

sub fullName {
  my ($self) = @_;
  return $self->firstname . " " . ucfirst(lc($self->surname));
}

sub all {
  my ($class, $schema) = @_;
  return $schema->resultset('ProfVideo')->search([
    {videoeng => {"!=" => ""}},
    {videofra => {"!=" => ""}},
    {videoLH => {"!=" => ""}},
    {videoLI => {"!=" => ""}}  # Although there are none of the latter
   ]);
}

sub sciper {
  my ($self) = @_;
  my $sciper_in_db = $self->_sciper;
  return $sciper_in_db if $sciper_in_db > 10000;
  if ($self->epflname eq "herve.lissek") {
    return 157878;
  }
  return undef;
}

sub check_sciper {
  my ($self) = @_;
  my $sciper = $self->sciper;
  die("Bogus sciper: $sciper for " . $self->epflname) unless $sciper > 10000;
}

package STISRV13;

use base qw(DBIx::Class::Schema);

__PACKAGE__->load_classes(qw(Article ProfVideo));

sub connect {
  my ($class, %opts) = @_;
  my $dsn = ($opts{-dsn} or 'DBI:mysql:database=stisrv13;host=127.0.0.1;port=3307');
  my $username = ($opts{-dsn} or 'root');
  my $password = $opts{-password};
  return $class->SUPER::connect($dsn, $username, $password, { mysql_enable_utf8 => 1});
}

1;
