/// A crop stage the farmer can choose. [value] is what is saved to the
/// database, and must be one of the ML model's growth_stage_values.
class GrowthStage {
  const GrowthStage(this.value, this.label, this.description);
  final String value;
  final String label;
  final String description;
}

const growthStages = [
  GrowthStage('vine_development', 'Vine growth',
      'Vines spread and more leaves form. Pump turns on when soil is below 60% and it is 29 °C or hotter, and turns off at 70%.'),
  GrowthStage('flowering', 'Flowering',
      'Male and female flowers appear. Pollinators move pollen to female flowers.'),
  GrowthStage('fruiting', 'Fruit set',
      'A pollinated female flower begins forming a small watermelon.'),
];
