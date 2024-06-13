package CBIL::ISA::StudyAssayFileReader;
use base qw(CBIL::ISA::Reader);

use strict;
use warnings;

use Scalar::Util qw(blessed);
use Data::Dumper;

sub setStudyAssayFile { $_[0]->{_study_assay_file} = $_[1] }
sub getStudyAssayFile { $_[0]->{_study_assay_file} }

sub setStudyAssay { $_[0]->{_study_assay} = $_[1] }
sub getStudyAssay { $_[0]->{_study_assay} }

sub setHeaderValues { $_[0]->{_header_values} = $_[1] }
sub getHeaderValues { $_[0]->{_header_values} }

sub setEntityNames { $_[0]->{_entity_names} = $_[1] }
sub getEntityNames { $_[0]->{_entity_names} }

sub setQualifierNames { $_[0]->{_qualifier_names} = $_[1] }
sub getQualifierNames { $_[0]->{_qualifier_names} }

sub new {
  my ($class, $file, $delimiter, $studyAssay) = @_;

  my $self = bless {}, $class;

  $self->initReader($delimiter);
  $self->setStudyAssayFile($file);
  $self->setStudyAssay($studyAssay);

  my ($fh);

  open($fh, "<:encoding(utf8)", $file) or die "Cannot open file $file for reading: $!";

  $self->setFh($fh);
  
  my $header = $self->readNextLine();

  $self->setHeaderValues($header);

  my @entityNames;
  my @qualifierNames;

  foreach my $headerValue (@$header) {
    #my ($entity, $junk, $qualifier) = $headerValue =~ m/([\w|\s]+)(\[(.+)\])?/;
    my @parsedHeader = $headerValue =~ m/([\w|\s]+)(\[([^\(]+(\(\w+:(.+)\))?)\])?/;

    my $entity = $parsedHeader[0];

    my $qualifier = $parsedHeader[2];

    if($parsedHeader[4]) {
      $qualifier = $parsedHeader[4];
    }

    my @words = map {ucfirst(lc($_))} split(/\s+/, $entity);
    $entity = join("", @words);

    # Map Header Values to objects
    $entity =~ s/Name$//;

    $entity = "Characteristic" if($entity eq "Characteristics");
    $entity = "ProtocolApplication" if($entity eq "ProtocolRef");
    $entity = "ArrayDesignFile" if($entity eq "ArrayDesignRef");
    
    push @entityNames, $entity;
    push @qualifierNames, $qualifier;
  }

  $self->setEntityNames(\@entityNames);
  $self->setQualifierNames(\@qualifierNames);

  return $self;
}

sub hasNextLine {
  my ($self) =  @_;

  my $fh = $self->getFh();

  return !eof($fh);
}

sub readLineToObjects {
  my ($self) = @_;

  my @rv;

  my @entityNames = @{$self->getEntityNames()};
  my @qualifierNames=  @{$self->getQualifierNames()};

  my $lineValues = $self->readNextLine();

  for(my $i = 0; $i < scalar @entityNames; $i++) {
    my $class = "CBIL::ISA::StudyAssayEntity::" . $entityNames[$i];
    my $lineValue = $lineValues->[$i];

    next if(!defined $lineValue || $lineValue eq "");

    my %hash = ( "_value" => $lineValue);

    eval "require $class";
    my $obj = eval {
      $class->new(\%hash);
    };
    if ($@) {
      die "Unable to create class $class: $@";
    }

    if(my $qualifierName = $qualifierNames[$i]) {
      $obj->setQualifier($qualifierName);
    }

    if($entityNames[$i] eq 'Assay') {
      $obj->setStudyAssay($self->getStudyAssay());
    }

    my $found;
  OUTER:
    foreach my $possibleParent (reverse @rv) {
      foreach my $expectedParent (@{$obj->getParents()}) {
        $expectedParent = "CBIL::ISA::StudyAssayEntity::" . $expectedParent;

        if($possibleParent->isa($expectedParent)) {
          my $qualifierContextMethod = $obj->qualifierContextMethod();

          my $attribute = $entityNames[$i] =~ /File$/ ? "File" :$entityNames[$i];
          
          if($possibleParent->hasAttribute($attribute)) {
          
            eval {
              if($obj->hasAttributes()) {
                $possibleParent->$qualifierContextMethod($obj);
              }
              else {
                $possibleParent->$qualifierContextMethod($obj->getValue());
              }
            };
            if ($@) {
              my $parentClass = blessed($possibleParent);
              die "Unable to call $qualifierContextMethod on $parentClass.  Trying to add or set $class: $@";
            }
          }
          $found = 1;
          last OUTER;
        }
      }
    }

    if($obj->hasAttributes()) {
      push @rv, $obj;
    }
  }

  @rv = map { $_->isSplittable() ? splitObject($_) : $_ } @rv;

  return \@rv;
}

sub splitObject {
  my ($obj) = @_;
  my $delimiter = $obj->getDelimiter();
  my @rv = ();

  # Do something like this:
  #
  # check that $obj->getValue and the scalar return values of $obj->getXXX (wjere XXX in $obj->getAttributeNames)
  # all split to the same number of values, N.
  #
  # there could be object attributes such as from $obj->getUnit
  # if so, I guess check that that has the same number of splits as $obj->getValue
  #
  # that could also have sub-objects? so potentially do this recursively?
  #
  # if all is good, create N new objects, ideally by a deep copy of $obj, then
  # go in to each copy and split and replace all the scalar values with the
  # appropriate value (e.g. for the second of three objects, replace 'aaa;bbb;ccc' with 'bbb')
  #
  # otherwise warn about the split count mismatch and return the original object?

  return @rv;
}

1;
