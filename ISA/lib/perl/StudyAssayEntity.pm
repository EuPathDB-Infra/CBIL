package CBIL::ISA::StudyAssayEntity;
use base qw(CBIL::ISA::Commentable);

use strict;

use Data::Dumper;
use Scalar::Util qw(blessed);

# subclasses must implement the following methods
sub isNode { return 0; }

# subclasses must consider these
sub getAttributeNames {
  my ($self) = @_;

  if($self->isNode()) {
    return ["Comment", "FactorValue"];
  }

  return ["Comment"];
}

sub getParents {
  return [];
}

sub qualifierContextMethod {
  my ($self) = @_;

  return "set" . $self->getEntityName();
}

sub getValue { $_[0]->{_value} }
sub setValue { $_[0]->{_value} = $_[1]}

sub hasAttributes {
  return scalar @{$_[0]->getAttributeNames()};
}


sub hasAttribute {
  my ($self, $attr) = @_;

  my $attributes = $self->getAttributeNames();
  foreach my $possible (@$attributes) {
    return 1 if($attr eq $possible);
  }
  return 0;
}

sub getEntityName {
  my ($self) = @_;

  my $className = blessed($self);
  my @sp = split(/::/, $className);

  return pop @sp;
}


# For Node Entities do the simple check that the value is the same
#  This requires the author of the isatab applied the Node Characteristics correctly
#  All other entity types are attributes and should not be thought of as the same entity
sub equals {
  my ($self, $obj) = @_;
  return 0 unless $self->isNode();
  return 0 unless $self->getValue() eq $obj->getValue();
  return 0 unless $self->getEntityName() eq $obj->getEntityName();
  return 1;

}


sub addFactorValue {
  my ($self, $factorValue) = @_;

  if($self->isNode()) {
    push @{$self->{_factor_values}}, $factorValue;
  }
  else {
    die "Cannot apply factor value to non node entity";
  }
}
sub getFactorValues { $_[0]->{_factor_values}  || [] }

#
# allow StudyAssayFileReader->readLineToObjects() to split this entity
# into multiple entities based on a delimiter
#
sub isSplittable { return 0 }
sub getSplitDelimiter { die "getSplitDelimiter() called on a non-splittable object" }

1;
