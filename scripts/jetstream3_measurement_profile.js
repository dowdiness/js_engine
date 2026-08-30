"use strict";

const DEFAULT_MEASUREMENT_PROFILE = "compatibility";

function resolveMeasurementProfile(name = DEFAULT_MEASUREMENT_PROFILE) {
  if (name === DEFAULT_MEASUREMENT_PROFILE) {
    return {
      name,
      countArguments: ["--iteration-count=2", "--worst-case-count=1"],
      iterationCountOverride: 2,
      worstCaseCountOverride: 1,
    };
  }
  if (name === "upstream-default") {
    return {
      name,
      countArguments: [],
      iterationCountOverride: null,
      worstCaseCountOverride: null,
    };
  }
  throw new Error(
    "--measurement-profile must be compatibility or upstream-default",
  );
}

module.exports = {
  DEFAULT_MEASUREMENT_PROFILE,
  resolveMeasurementProfile,
};
