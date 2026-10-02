// The bridge between the Calculum website's calculator modules and the app.
// scripts/build-engine.sh bundles this file with those modules into
// Calculum/Resources/engine.js. Every function returns a JSON string.

import { calculators, categories, getCalculator } from '@site/data/catalog.js';
import { calculateTool, getToolSpec } from '@site/data/tool-specs.js';
import {
  countryProfiles,
  fromDisplayValue,
  getActiveProfile,
  getCurrencySymbol,
  getDisplaySuffix,
  setActiveCountry,
  toDisplayValue,
} from '@site/data/localization.js';
import { getCountryFieldOverrides, getToolCountryContext } from '@site/data/country-rules.js';
import { getEditorialGuide } from '@site/data/editorial-guides.js';
import { getAuthoritativeSources } from '@site/data/authoritative-sources.js';
import { financialToolNotice, isFinancialCalculator } from '@site/data/financial-notice.js';
import { getProjectionChart, hasProjectionChart } from '@site/data/projection-charts.js';
import { getOutputMetric, getSensitivityRange } from '@site/scripts/scenario-workspace.js';

const json = (value) => JSON.stringify(value ?? null);

function catalog() {
  return json({
    categories: categories.map(({ slug, name, shortName, mark, description }) => ({
      slug, name, shortName, mark, description,
    })),
    calculators: calculators.map(({ id, slug, title, category, question }) => ({
      id, slug, title, category, question,
    })),
    countries: countryProfiles,
    financialNotice: financialToolNotice,
  });
}

function setCountry(code) {
  return json(setActiveCountry(code));
}

function displayField(field, override, profile) {
  const unit = field.suffix ?? '';
  const step = Number(field.step);
  const label = override?.label ?? field.label;
  return {
    name: field.name,
    label: label.charAt(0).toUpperCase() + label.slice(1),
    kind: field.type === 'select' ? 'select' : 'number',
    prefix: field.prefix === '$' ? getCurrencySymbol(profile) : (field.prefix ?? null),
    suffix: unit ? getDisplaySuffix(unit, profile) : null,
    unit,
    step: Number.isFinite(step) && step > 0 ? step : null,
    options: field.options?.map(({ value, label }) => ({ value: Number(value), label })) ?? null,
  };
}

function guideFor(guide) {
  if (!guide) return null;
  return {
    intro: guide.intro,
    takeaway: guide.example.takeaway,
    interpretation: guide.interpretation ?? [],
    edgeCases: guide.edgeCases ?? [],
    drivers: guide.deepDive?.drivers ?? [],
    mistakes: guide.deepDive?.mistakes ?? [],
    useFor: guide.deepDive?.useFor ?? '',
    notFor: guide.deepDive?.notFor ?? '',
  };
}

function examplesFor(guide) {
  if (!guide) return [];
  return [
    { title: guide.example.title, description: guide.example.setup, values: guide.example.values },
    ...(guide.deepDive?.scenarios ?? []).slice(0, 2).map((scenario) => ({
      title: scenario.title,
      description: scenario.description ?? `Use ${scenario.input} and keep the other values unchanged.`,
      values: scenario.values,
    })),
  ];
}

function tool(slug) {
  const calculator = getCalculator(slug);
  const spec = getToolSpec(slug);
  if (!calculator || !spec) return json(null);
  const profile = getActiveProfile();
  const overrides = getCountryFieldOverrides(slug, profile);
  const guide = getEditorialGuide(slug, calculator, spec);
  const context = getToolCountryContext(slug, profile);

  return json({
    slug,
    eyebrow: spec.eyebrow,
    formula: spec.formula,
    assumptions: spec.assumptions ?? [],
    fields: spec.fields.map((field) => displayField(field, overrides[field.name], profile)),
    defaults: Object.fromEntries(spec.fields.map((field) => [
      field.name,
      Number(overrides[field.name]?.defaultValue ?? field.value),
    ])),
    guide: guideFor(guide),
    examples: examplesFor(guide),
    sources: getAuthoritativeSources(slug, profile).map(({ label, organization, scope, note, url }) => ({
      label, organization, scope, note, url,
    })),
    context: context
      ? { title: context.title, body: context.body, sourceLabel: context.source?.label ?? null, sourceURL: context.source?.url ?? null }
      : null,
    financial: isFinancialCalculator(calculator),
    hasProjection: hasProjectionChart(slug),
  });
}

function outputFor(output, profile) {
  if (!output) return null;
  const metric = getOutputMetric(output, profile);
  return {
    primary: String(output.primary),
    label: String(output.label ?? ''),
    details: (output.details ?? []).map(([label, value]) => [String(label), String(value)]),
    note: String(output.note ?? ''),
    metric: metric && Number.isFinite(metric.value) ? { value: metric.value, label: metric.label } : null,
  };
}

function calculate(slug, valuesJSON) {
  try {
    return json(outputFor(calculateTool(slug, JSON.parse(valuesJSON)), getActiveProfile()));
  } catch {
    return json(null);
  }
}

function sensitivity(slug, valuesJSON, fieldName) {
  const spec = getToolSpec(slug);
  const field = spec?.fields.find(({ name }) => name === fieldName);
  if (!field || field.type === 'select') return json(null);
  const profile = getActiveProfile();
  const unit = field.suffix ?? '';
  const values = JSON.parse(valuesJSON);

  try {
    const current = getOutputMetric(calculateTool(slug, values), profile);
    if (!current || !Number.isFinite(current.value)) return json(null);
    const { lower, upper } = getSensitivityRange(values[fieldName], field.min, field.max, field.step);
    const count = 41;
    const points = [];
    for (let index = 0; index < count; index += 1) {
      const x = lower + ((upper - lower) * index) / (count - 1);
      const metric = getOutputMetric(calculateTool(slug, { ...values, [fieldName]: x }), profile);
      if (metric && metric.label === current.label && Number.isFinite(metric.value)) {
        points.push({ x: toDisplayValue(x, unit, profile), y: metric.value });
      }
    }
    if (points.length < 2) return json(null);
    return json({
      metricLabel: current.label,
      currentX: toDisplayValue(Number(values[fieldName]), unit, profile),
      currentY: current.value,
      points,
    });
  } catch {
    return json(null);
  }
}

function projection(slug, valuesJSON) {
  const chart = getProjectionChart(slug, JSON.parse(valuesJSON));
  if (!chart) return json(null);
  const keys = chart.series.map(({ key }) => key);
  return json({
    title: chart.title,
    description: chart.description ?? '',
    valueType: chart.valueType ?? 'number',
    series: chart.series.map(({ key, label }) => ({ key, label })),
    points: chart.points.map((point) => ({
      x: point.x,
      label: chart.xFormatter ? chart.xFormatter(point.x) : String(point.x),
      values: Object.fromEntries(keys.map((key) => [key, Number(point.values[key])]).filter(([, value]) => Number.isFinite(value))),
    })),
  });
}

function toDisplay(value, unit) {
  return toDisplayValue(Number(value), unit, getActiveProfile());
}

function fromDisplay(value, unit) {
  return fromDisplayValue(Number(value), unit, getActiveProfile());
}

globalThis.CalculumEngine = {
  catalog,
  setCountry,
  tool,
  calculate,
  sensitivity,
  projection,
  toDisplay,
  fromDisplay,
};
