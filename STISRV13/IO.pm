package STISRV13::IO;

use JSON;
use IO::All;
use YAML;

use base qw(Exporter);
our @EXPORT = our @EXPORT_OK =
  qw(io_local_image load_text load_json save_json load_yaml save_yaml load_secrets);


sub io_local_image {
  my ($basename) = @_;
  return io->file("images/$basename");
}

sub load_text { scalar io(shift)->slurp }
sub load_json { decode_json(load_text(shift)) }
sub load_yaml { YAML::LoadFile(shift) }
sub load_secrets { load_yaml("secrets.yaml") }

sub save_json {
  my ($to_file, $struct) = @_;
  # Unlike encode_json, the OO version of JSON defaults to producing a
  # string of characters (not bytes):
  JSON->new->pretty->encode($struct) > io($to_file)->utf8;
}

sub save_yaml {
  my ($to_file, $struct) = @_;
  YAML::Dump($struct) > io($to_file)->utf8;
}
