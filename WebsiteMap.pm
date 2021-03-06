package WebsiteMap;

use JSON;
use Debug::Statements;
use Benchmark qw(timeit timestr);

use GML;

sub new {
  my ($class, $newsatone_meta, $website_gml) = @_;

  return bless {
    newsatone_meta => $newsatone_meta,
    website_gml    => $website_gml
  }, $class;
}

sub ancestry {
  my ($self, $vertex) = @_;
  return $self->_website_graph->ancestry($vertex);
}

sub _website_graph {
  my ($self) = @_;
  if (! $self->{website_graph}) {
    my $t = timeit(1, sub {
      $self->{website_graph} = decode_gml($self->{website_gml});
    });
    warn sprintf("Loaded website graph in %s s\n", timestr($t));
  }
  return $self->{website_graph};
}

sub _newsatone_inverted {
  my ($self) = @_;
  if (! $self->{_newsatone}) {
    my $t = timeit(1, sub {
      while (my ($url, $newsatone_cgi_params) = each %{$self->{newsatone_meta}}) {
        %cgi_params = map { m/(.*)=(.*)/ } (split(/&(?:amp;)*/, $newsatone_cgi_params));
        my $lang = substr($cgi_params{lang}, 0, 2);
        die $newsatone_cgi_params unless $lang;
        push @{$self->{_newsatone}->{$cgi_params{id}}->{$lang}}, $url;
      }
    });
    warn sprintf("Inverted newsatone meta in %s s\n", timestr($t));
  }
  return $self->{_newsatone};
}

sub get_urls {
  my ($self, $rss_id, $lang) = @_;
  return grep {! m|/op/edit/| } @{$self->_newsatone_inverted->{$rss_id}->{$lang}};
}

sub find_vertex {
  my ($self, $url) = @_;
  my @results = $self->_website_graph->find_vertices_by_label($url);
  return wantarray ? @results: $results[0];
}

1;
