package GML;

use strict;
use v5.26;

use base qw(Exporter); our @EXPORT = qw(decode_gml);

use Parse::RecDescent;
sub decode_gml {
  my ($gml_txt) = @_;

  if ($ENV{DEBUG}) {
    $::RD_ERRORS = 1;       # Report fatal errors
    $::RD_WARN   = 1;       # Also report non-fatal problems
    $::RD_HINT   = 1;       # Also suggest remedies
    $::RD_TRACE  = 1;       # Trace the parsing nitty-gritties
  }

  state $parser = do {
    Parse::RecDescent->new(q(
      # See http://www.fim.uni-passau.de/fileadmin/files/lehrstuhl/brandenburg/projekte/gml/gml-technical-report.pdf

      graph :         'graph'  '['      kvs    thing_in_graph(s?) ']' {
         my ( undef,  undef,   undef,  $kvs,  $things) = @item;
         $return = new GML::Graph(
           %$kvs,
           edges    => [grep { $_->isa("GML::Edge") }   @$things],
           vertices => [grep { $_->isa("GML::Vertex") } @$things]
         );
      }

      thing_in_graph : node | edge

      node : "node" '[' kvs ']' { $return = GML::Vertex->new(%{$item[-2]}); }
      edge : "edge" '[' kvs ']' { $return = GML::Edge->new(%{$item[-2]}); }

      kv : key value { my (undef, $k, $v) = @item; $return = [$k => $v] }
      kvs : kv(s?) { my (undef, $kvs_ref) = @item; $return = {map {@$_} @$kvs_ref}  }

      key: "comment" | "directed" | "IsPlanar" | "id" | "label" | "source" | "target"

      value : integer | quoted_string

      quoted_string : <perl_quotelike>  { $return = $item[1]->[2] }

      integer : /[-+]?\d+/
     ))
  };

  return $parser->graph($gml_txt);
}

sub GML::Edge::new {
  my $class = shift;
  return bless { @_ }, $class;
}

sub GML::Vertex::new {
  my $class = shift;
  return bless { @_ }, $class;
}

package GML::Graph;

sub new {
  my ($class, %opts) = @_;
  return bless { %opts }, $class;
}

sub find_vertices_by_label {
  my ($self, $label) = @_;
  return grep { $_->{label} eq $label } @{$self->{vertices}};
}
