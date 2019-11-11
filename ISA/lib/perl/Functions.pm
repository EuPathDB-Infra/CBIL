package CBIL::ISA::Functions;
require Exporter;
@ISA = qw(Exporter);

@EXPORT_OK = qw(makeObjectFromHash makeOntologyTerm);

use Scalar::Util qw/blessed looks_like_number/;

use Date::Manip qw(Date_Init ParseDate UnixDate DateCalc);

use strict;
use warnings;

use CBIL::ISA::OntologyTerm;
use Date::Parse qw/strptime/;

use File::Basename;

use Data::Dumper;
use Digest::SHA;

sub getOntologyMapping {$_[0]->{_ontology_mapping} }
sub getOntologySources {$_[0]->{_ontology_sources} }
sub getValueMappingFile {$_[0]->{_valueMappingFile} }

sub getValueMapping {$_[0]->{_valueMapping} }
sub setValueMapping {$_[0]->{_valueMapping} = $_[1] }

sub getDateObfuscationFile {$_[0]->{_dateObfuscationFile} }

sub getDateObfuscationOutFh {$_[0]->{_dateObfuscationOutFh} }
sub setDateObfuscationOutFh {$_[0]->{_dateObfuscationOutFh} = $_[1] }

sub getDateObfuscation {$_[0]->{_dateObfuscation} }
sub setDateObfuscation {$_[0]->{_dateObfuscation} = $_[1] }

sub new {
  my ($class, $args) = @_;

  my $self = bless $args, $class;

  my $valueMappingFile = $self->getValueMappingFile();

  my $valueMapping = {};
  if($valueMappingFile) {
    open(FILE, $valueMappingFile) or die "Cannot open file $valueMappingFile for reading: $!";

    while(<FILE>) {
      chomp;

      my ($qualName, $qualSourceId, $in, $out) = split(/\t/, $_);

      my $lcIn = lc($in);

      # I think case for source_ids matters so these need to match exactly
      $valueMapping->{$qualSourceId}->{$lcIn} = $out;

      if($qualName) {
        my $lcQualName = lc $qualName;
        $valueMapping->{$lcQualName}->{$lcIn} = $out;
      }
    }
    close FILE;
  }
  $self->setValueMapping($valueMapping);

  my $dateObfuscationFile = $self->getDateObfuscationFile();
  my $dateObfuscation = {};
  if($dateObfuscationFile) {
    open(FILE, $dateObfuscationFile) or die "Cannot open file $dateObfuscationFile for reading: $!";

    while(<FILE>) {
      chomp;
      my ($recordTypeSourceId, $recordPrimaryKey, $delta) = split(/\t/, $_);
      #die("$dateObfuscationFile has a bad format: [$recordTypeSourceId] [$recordPrimaryKey] [$delta]\n") unless($recordTypeSourceId && $recordPrimaryKey && $delta);
      $dateObfuscation->{$recordTypeSourceId}->{$recordPrimaryKey} = $delta;
    }
    close FILE;

    # Important to append here
    open(my $dateObfuscationOutFile, ">>$dateObfuscationFile") or die "Cannot open file $dateObfuscationFile for writing: $!";
    $self->setDateObfuscationOutFh($dateObfuscationOutFile);
  }
  $self->setDateObfuscation($dateObfuscation);

  return $self;
}



sub enforceYesNoForBoolean {
  my ($self, $obj) = @_;

  my $value = $obj->getValue();

  return undef unless defined($value);# && $value ne "";
  if($value =~ /^\d+$/){ $value = int($value); } # remove leading zeros if $value is integer;

  my %allowedValues = (
    "1" => "Yes",
    "yes" => "Yes",
    "true" => "Yes",
    "y" => "Yes",
    "0" => "No",
    "no" => "No",
    "n" => "No",
    "false" => "No",
    "" => "",
  );

  my $cv = $allowedValues{lc($value)};

  if(defined($cv)) {
    return $obj->setValue($cv);
  }

  die "Could not map value [$value] to Yes or No\n" .  Dumper($obj);
}


sub cacheDelta {
  my ($self, $sourceId, $primaryKey, $deltaString) = @_;

  # print to cache file
  my $dateObfuscationOutFh = $self->getDateObfuscationOutFh();
  my $dateObfuscation = $self->getDateObfuscation();

  print $dateObfuscationOutFh "$sourceId\t$primaryKey\t$deltaString\n";
  $dateObfuscation->{$sourceId}->{$primaryKey} = $deltaString;
}


sub calculateDelta {
  my ($self) = @_;

  my $plusOrMinusDays = 7; # TODO: parameterize this

  my $direction = int (rand(2)) ? 1 : -1;

  my $magnitude = 1 + int(rand($plusOrMinusDays));

  my $days = $direction * $magnitude; 

  my $deltaString = "0:0:0:$days:0:0:0";

  return $deltaString;
}


sub internalDateWithObfuscation {
  my ($self, $obj, $parentObj, $parentInputObjs, $dateFormat) = @_;

  my $value = $obj->getValue();

  # deal with "Mon Year" values by setting the day to the first day of the month
  if(defined($value) && ($value =~ /^\w{3}\s*\d{2}(\d{2})?$/)) {
    $value = "1 " . $value;
  }

  Date_Init($dateFormat); 

  my $formattedDate;
  if($self->getDateObfuscationFile()) {
    my $dateObfuscation = $self->getDateObfuscation();

    my $delta;

    if($parentObj->isNode()) {
      my $nodeId = $parentObj->getValue();

      my $materialType = $parentObj->getMaterialType();
      my $materialTypeSourceId = $materialType->getTermAccessionNumber();
      $delta = $dateObfuscation->{$materialTypeSourceId}->{$nodeId};

      unless($delta) {

        # if I have inputs and one of my inputs has a delta, cache that and use for self
        if(scalar @$parentInputObjs > 0) {
          foreach my $input(@$parentInputObjs) {
            my $inputNodeId = $input->getValue();

            my $inputMaterialType = $input->getMaterialType();
            my $inputMaterialTypeSourceId = $inputMaterialType->getTermAccessionNumber();

            if($delta && $delta ne $dateObfuscation->{$inputMaterialTypeSourceId}->{$inputNodeId}) {
              die "2 deltas found for parents of $nodeId" if($dateObfuscation->{$inputMaterialTypeSourceId}->{$inputNodeId});
            }

            $delta = $dateObfuscation->{$inputMaterialTypeSourceId}->{$inputNodeId};
            $self->cacheDelta($materialTypeSourceId, $nodeId, $delta) if($delta);
            last;
          }
          # I had a parent, but it didn't have a delta
          unless($delta) {
          #  die "No delta available for $nodeId";
          #  TODO set a property for a fallback callback
         	  $delta = $self->calculateDelta();
         	  $self->cacheDelta($materialTypeSourceId, $nodeId, $delta);
          }
        }

        # else, calculate new delta and cache for self
        unless($delta) {
          $delta = $self->calculateDelta();
          $self->cacheDelta($materialTypeSourceId, $nodeId, $delta);
        }
      }
    }
    else {
      # TODO: deal with protocol params
      die "Only Characteristic Values currently allow date obfuscation";
    }

    my $date = DateCalc($value, $delta); 
    $formattedDate = UnixDate($date, "%Y-%m-%d");
  }
  else {
    die "No dateObfuscationFile was not provided";
  }

  $obj->setValue($formattedDate);

  unless($value){
    return $value;
  }
  unless(defined($formattedDate)) {
    die "Date Format not supported for [$value]=[$formattedDate], OR bad date obfuscation file\n" . $obj->getAlternativeQualifier . "\n" . Dumper($obj);
  }

  return $formattedDate;
}



sub formatEuroDate {
  my ($self, $obj, $parentObj) = @_;

  my $value = $obj->getValue();

  # deal with "Mon Year" values by setting the day to the first day of the month
  if($value =~ /^\w{3}\s*\d{2}(\d{2})?$/) {
    $value = "1 " . $value;
  }

  Date_Init("DateFormat=non-US"); 

  my $formattedDate = UnixDate(ParseDate($value), "%Y-%m-%d");

  $obj->setValue($formattedDate);

  unless($formattedDate) {
    die "Date Format not supported for [$value]\n";
  }

  return $formattedDate;
}



sub formatHouseholdId {
  my ($self, $obj) = @_;

  my $value = $obj->getValue();

  if ($value=~/^HH\d+$/i) {
    $value = uc($value);
    $obj->setValue($value);
  }
  else {
    $obj->setValue("HH$value");
  }
  return $obj;
}

sub valueIsMappedValue {
  my ($self, $obj) = @_;

  my $value = $obj->getValue();
  my $qualSourceId = $obj->getQualifier();

  my $valueMapping = $self->getValueMapping();

  my $qualifierValues = $valueMapping->{$qualSourceId};
  unless($qualifierValues){
    my $qualName = $obj->getAlternativeQualifier();
    $qualifierValues = $valueMapping->{$qualName};
  }

  unless(defined($value) && ($value ne "")){ return }

  if($qualifierValues) {
    my $lcValue = lc($value);
    unless(defined($value) || defined($qualifierValues->{':::undef:::'})){ return; }
    unless(defined($lcValue)){ $lcValue = ':::undef:::';}
    my $newValue = $qualifierValues->{$lcValue};
    unless(defined($newValue)){
      foreach my $regex ( grep { /^{{.*}}$/ } keys %$qualifierValues){
        my ($test) = ($regex =~ /^\{\{(.*)\}\}$/);
        $test = qr/$test/;
        if($lcValue =~ $test){
          $newValue = $qualifierValues->{$regex};
          last;
        }
        else {
          printf STDERR ("NO MATCH $lcValue =~ $test\n");
        }
      }
    }
    if(defined($newValue)){
      if(uc($newValue) eq ':::UNDEF:::'){
        $obj->setValue(undef);
      }
      elsif($newValue || $newValue eq '0') {
        $obj->setValue($newValue);
      }
    }
  }
}



sub valueIsMappedValueAltQualifier {
  my ($self, $obj) = @_;

  my $value = lc $obj->getValue();
  my $altQualifier = $obj->getAlternativeQualifier();

  my $valueMapping = $self->getValueMapping();

  my $qualifierValues = $valueMapping->{$altQualifier};


  if($qualifierValues) {
    my $lcValue = lc($value);

    my $newValue = $qualifierValues->{$lcValue};
    $newValue = undef unless(defined($newValue));

    if(exists $qualifierValues->{$value}) {
      $obj->setValue($newValue);
    }
  }
}



sub valueIsOntologyTerm {
  my ($self, $obj) = @_;

  my $value = $obj->getValue();

  my $omType = blessed($obj) eq 'CBIL::ISA::StudyAssayEntity::Characteristic' ? 'characteristicValue' : 'protocolParameterValue';

  $value = basename $value; # strip prefix if IRI
  my ($valuePrefix) = $value =~ /^(\w+)_|:/;

  my $om = $self->getOntologyMapping();
  my $os = $self->getOntologySources();

  if($os->{lc($valuePrefix)}) {
    $obj->setTermAccessionNumber($value);
    $obj->setTermSourceRef($valuePrefix);
  }
  elsif(my $hash = $om->{lc($value)}->{$omType}) {
    my $sourceId = $hash->{source_id};
    my ($termSource) = $sourceId =~ /^(\w+)_|:/;

    $obj->setTermAccessionNumber($sourceId);
    $obj->setTermSourceRef($termSource);
  }
  else {
    die "Could not determine Accession Number for: [$value]";
  }
}

sub splitUnitFromValue {
  my ($self, $obj) = @_;

  my $om = $self->getOntologyMapping();
  my $valueOrig = $obj->getValue();

  my ($value, $unitString) = split(/\s+/, $valueOrig);
  $obj->setValue($value);

  my $class = "CBIL::ISA::StudyAssayEntity::Unit";

  my $unitSourceId = $om->{lc($unitString)}->{unit}->{source_id};
  if (defined $value) {
    unless($unitSourceId) {
      die "Could not find ontologyTerm for Unit:  $unitString";
    }

    my $unit = &makeOntologyTerm($unitSourceId, $unitString, $class);

    $obj->setUnit($unit);
  }
  else {
    $obj->setUnit(undef);
  }
}


sub setUnitToYear {
  my ($self, $obj) = @_;

  my $YEAR_SOURCE_ID = "UO_0000036";

  my $unit = $obj->getUnit();
  my $unitSourceId = $unit->getTermAccessionNumber();
  return if $unitSourceId eq $YEAR_SOURCE_ID;

  my $conversionFactor;
  if ($unitSourceId eq "UO_0000035") {     # month
    $conversionFactor = 12;
  } elsif ($unitSourceId eq "UO_0000034") { # week
    $conversionFactor = 52;
  } elsif ($unitSourceId eq "UO_0000033") {  # day
    $conversionFactor = 365.25;
  } else {
    die "unknown unitSourceId \"$unitSourceId\"";
  }

  my $value = $obj->getValue();
  $obj->setValue($value / $conversionFactor);
  $unit->setTermAccessionNumber("$YEAR_SOURCE_ID");
  $unit->setTerm("year");
}


sub formatDate {
  my ($self, $obj) = @_;

  my $value = $obj->getValue();

  Date_Init("DateFormat=US"); 

  my $formattedDate = UnixDate(ParseDate($value), "%Y-%m-%d");

  $obj->setValue($formattedDate);

  unless($formattedDate) {
    die "Date Format not supported for $value\n";
  }

  return $formattedDate;
}

sub formatDateWithObfuscation {
  my ($self, $obj, $parentObj, $parentInputObjs) = @_;

  $self->internalDateWithObfuscation($obj, $parentObj, $parentInputObjs, "DateFormat=US");
}

sub formatEuroDateWithObfuscation {
  my ($self, $obj, $parentObj, $parentInputObjs) = @_;

  $self->internalDateWithObfuscation($obj, $parentObj, $parentInputObjs, "DateFormat=non-US");
}

sub formatTime {
  my ($self, $obj) = @_;

  my $value = $obj->getValue();
  if($value =~ /^0:(\d\d\w\w)$/){ 
    $value =~ s/^0:(\d\d\w\w)$/12:$1/;
    Date_Init("DateFormat=US"); 
    my $formattedTime = UnixDate(ParseDate($value), "%H%M");
    $obj->setValue($formattedTime);
    unless($formattedTime) {
      die "(formatTime) Format not supported for $value\n" . Dumper $obj;
    }
    return $formattedTime;
  }
  elsif($value =~ /^\d{4}$/){
   #my $newvalue =~ s/^(\d\d)(\d\d)/\1:\2$/;
    my $hour = $value / 100;
    my $min = $value % 100;
    my $formattedTime = sprintf("%02d:%02d", $hour, $min);
    $obj->setValue($formattedTime);
    unless($formattedTime) {
      die "(formatTime) Format not supported for $value\n" . Dumper $obj;
    }
    return $formattedTime;
  }
  else {
    Date_Init("DateFormat=US"); 
    my $formattedTime = UnixDate(ParseDate($value), "%H:%M");
    $obj->setValue($formattedTime);
    unless($formattedTime) {
      die "(formatTime) Format not supported for $value\n" . Dumper $obj;
    }
    return $formattedTime;
  }
}

sub formatTimeHHMMtoDecimal {
  my ($self, $obj) = @_;
  my $value = $obj->getValue();
  return unless defined $value;
  my $hr = sprintf("%d", $value / 100);
  my $min = $value % 100;
  $min = $min / 60;
  my $time = sprintf('%.03f',$hr + $min);
  $obj->setValue($time);
  return $time;
}

sub makeOntologyTerm {
  my ($sourceId, $termName, $class) = @_;

  my ($termSource) = $sourceId =~ /^(\w+)_|:/;

  $class = "CBIL::ISA::OntologyTerm" unless($class);

  my $hash = {term_source_ref => $termSource,
              term_accession_number => $sourceId,
              term => $termName
  };
  
  
  return &makeObjectFromHash($class, $hash);
  
}

sub formatSentenceCase {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  if(defined($val)){
    return $obj->setValue(ucfirst(lc($val)));
  }
  return;
}

sub formatTitleCase {
  my ($self, $obj) = @_;
  my $val = join(" ", map { ucfirst } split(/\s/, lc($obj->getValue())));
  return $obj->setValue($val);
}

sub formatNumeric {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
    return unless defined($val);
  if($val =~ /^na$/i){
    return $obj->setValue(undef);
  }
}
sub formatInteger {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  return unless defined($val);
  if(looks_like_number($val)){
    return $obj->setValue(sprintf("%d",$val));
  }
}

sub formatNumericFiltered {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  unless(looks_like_number($val)){
    return $obj->setValue(undef);
  }
}

sub formatClinicalFtoC {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  return unless defined($val);
  return unless $val > 65;
  return $obj->setValue((($val - 32) * 5) / 9);
}

sub formatFtoC {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  return unless defined($val);
  return $obj->setValue((($val - 32) * 5) / 9);
}

sub formatQuotation {
  my ($self, $obj) = @_;
  return $obj->setValue(sprintf("\"%s\"",$obj->getValue()));
}

sub parseDmsCoordinate {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  my ($decVal,$min,$sec) = ( $val =~ m/([+-]?\d+\.?\d*)/g );
  my ($card) = ($val =~ /([NSEWnsew])/);
  if($min){ $decVal += $min/60; }
  if($sec){ $decVal += $sec/3600; }
  if(defined($card) && $card =~ /[SWsw]/) { $decVal = -$decVal; }
  return $obj->setValue($decVal);
}

sub digestSHAHex16 {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  return unless defined($val);
  return $obj->setValue(substr(Digest::SHA::sha1_hex($val),0,16));
}

sub encryptSuffix1 {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  return unless defined($val);
  my ($prefix,$suffix1,@suffixN) = split(/_/, $val);
  $suffix1 = substr(Digest::SHA::sha1_hex($suffix1),0,16);
  my $newId = join("_", $prefix, $suffix1, @suffixN); 
  return $obj->setValue($newId);
}

sub encryptSuffix2 {
  my ($self, $obj) = @_;
  my $val = $obj->getValue();
  return unless defined($val);
  my @id = split(/_/, $val);
  $id[2] = substr(Digest::SHA::sha1_hex($id[2]),0,16);
  my $newId = join("_", @id); 
  return $obj->setValue($newId);
}

sub idObfuscateDate1 {
  my ($self, $node, $type) = @_;
  my $materialTypeSourceId = $self->getOntologyMapping()->{$type}->{'materialType'}->{'source_id'};
  my $nodeId = $node->getValue();
  die unless defined($nodeId);
  my $local = {};
  ($local->{dateOrig}) = ($nodeId =~ /^[^_]+_([^_]+)/);
  if(lc($local->{dateOrig}) eq "na"){
    $nodeId =~ s/_na/_nax/i; # make it different
    return $node->setValue($nodeId);
  }
  ## OK I spent about 4 hours debugging this shit
  ## apparently a leading 0 in "09-07-2009" will cause ParseDate to read it as 2009-07-20
  my $dateOrig = $local->{dateOrig}; # save this for regex replace
  $local->{dateOrig} =~ s/^0//;
  $local->{formattedDate} = "NOT SET";
  my $dateObfuscation = $self->getDateObfuscation();
  my $delta = $dateObfuscation->{$materialTypeSourceId}->{$nodeId};
  if($delta) {
    # Date_Init("DateFormat=US");
    $local->{unixDate} = ParseDate($local->{dateOrig});
    unless($local->{unixDate}){
      Date_Init("DateFormat=US");
      $local->{unixDate} = ParseDate($local->{dateOrig});
    }
    unless($local->{unixDate}){
      warn "Cannot parse date: " . $local->{dateOrig};
    }
    $local->{preDate} = UnixDate($local->{unixDate}, "%Y-%m-%d");
    $local->{date} = DateCalc($local->{unixDate}, $delta);
    $local->{formattedDate} = UnixDate($local->{date}, "%Y-%m-%d");
  }
  else {
    die "MISSINGDELTA:$type:$materialTypeSourceId:$nodeId";
  }
  my $newId = $nodeId; 
  die "No date in $nodeId\n" . Dumper $local unless $local->{dateOrig} && $local->{formattedDate}; 
  $newId =~ s/$dateOrig/$local->{formattedDate}/;
  return $node->setValue($newId);
}

sub makeObjectFromHash {
  my ($class, $hash) = @_;

  eval "require $class";
  my $obj = eval {
    $class->new($hash);
  };
  if ($@) {
    die "Unable to create class $class: $@";
  }

  return $obj;
}

1;

