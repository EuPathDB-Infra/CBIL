package CBIL::ISA::StudyAssayEntity::Characteristic;
use base qw(CBIL::ISA::OntologyTermWithQualifier);

use strict;

sub getParents {
  return ["Source", "Sample", "Extract", "LabeledExtract", "Assay" ];
}

# @override
sub setTerm {
  my ($self, $value) = @_;

  my %commonTerms = ('no', 1,
                     'yes', 1,
                     'negative', 1,
                     'positive', 1,
                     'not done', 1,
                     'not applicable', 1,
                     'not known', 1,
                     'none', 1,
      );


  my $lcValue = lc($value);
  my $ucfirstValue = ucfirst($value);
  if($commonTerms{$lcValue}) {
    $self->{_term} = $ucfirstValue;
  }
  else {
    $self->{_term} = $value;
  }

}

sub setUnit { $_[0]->{_unit} = $_[1] }
sub getUnit { $_[0]->{_unit} }

sub getAttributeNames {
  my ($self) = @_;

  my @attributeQualifiers = ("Unit");

  my $attrs = $self->SUPER::getAttributeNames();

  push @{$attrs}, @attributeQualifiers;

  return $attrs;
}

sub qualifierContextMethod {
  return "addCharacteristic";
}

sub isSplittable { return 1; }
sub getSplitDelimiter { return qr/;\s*/ }

1;
