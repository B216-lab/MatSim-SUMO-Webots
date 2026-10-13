#!/usr/bin/env bash
# Prepare MATSim inputs from the Karl Marx / central Irkutsk SUMO network.
# base/network/irkutsk.net.xml is an MVP placeholder (copy of the street net), not a full-city extract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUMO_NET="${SUMO_NET:-$ROOT/streets/karla-marksa/network/karla_marksa.net.xml}"
MATSIM_DIR="$ROOT/base/matsim"
BASE_NET_DIR="$ROOT/base/network"
BASE_DEMAND_DIR="$ROOT/base/demand"
AGENTS="${AGENTS:-400}"
ITERS="${ITERS:-5}"
MATSIM_IMAGE="${MATSIM_IMAGE:-traffic-sim/matsim:15.0}"

mkdir -p "$MATSIM_DIR" "$BASE_NET_DIR" "$BASE_DEMAND_DIR"

echo "==> Copy SUMO street net → base/network/irkutsk.net.xml (MVP placeholder)"
cp -f "$SUMO_NET" "$BASE_NET_DIR/irkutsk.net.xml"

echo "==> SUMO → MATSim network"
python3 "$ROOT/base/scripts/sumo_to_matsim_network.py" \
  --sumo-net "$SUMO_NET" \
  --out "$MATSIM_DIR/network.xml"

echo "==> Clean MATSim network (largest SCC)"
mkdir -p "$MATSIM_DIR/output"
docker run --rm --entrypoint bash \
  -v "$MATSIM_DIR:/matsim/input" \
  "$MATSIM_IMAGE" \
  -c 'cd /matsim && java -cp "/matsim/matsim.jar:/matsim/libs/*" org.matsim.run.NetworkCleaner /matsim/input/network.xml /matsim/input/network_clean.xml'
cp -f "$MATSIM_DIR/network_clean.xml" "$MATSIM_DIR/network.xml"

echo "==> Synthetic population against cleaned links (AGENTS=${AGENTS})"
python3 "$ROOT/base/scripts/gen_synthetic_population.py" \
  --sumo-net "$SUMO_NET" \
  --matsim-network "$MATSIM_DIR/network.xml" \
  --out "$MATSIM_DIR/population.xml" \
  --agents "$AGENTS"

# Rewrite config with modest iterations for local/docker demo.
# Paths are absolute inside the traffic-sim/matsim container layout.
cat > "$MATSIM_DIR/config.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE config SYSTEM "http://www.matsim.org/files/dtd/config_v2.dtd">
<config>
    <module name="global">
        <param name="coordinateSystem" value="EPSG:32647"/>
        <param name="numberOfThreads" value="4"/>
        <param name="randomSeed" value="4711"/>
    </module>
    <module name="network">
        <param name="inputNetworkFile" value="/matsim/input/network.xml"/>
    </module>
    <module name="plans">
        <param name="inputPlansFile" value="/matsim/input/population.xml"/>
    </module>
    <module name="controller">
        <param name="outputDirectory" value="/matsim/output"/>
        <param name="firstIteration" value="0"/>
        <param name="lastIteration" value="${ITERS}"/>
        <param name="writeEventsInterval" value="${ITERS}"/>
        <param name="writePlansInterval" value="${ITERS}"/>
        <param name="overwriteFiles" value="deleteDirectoryIfExists"/>
    </module>
    <module name="qsim">
        <param name="startTime" value="00:00:00"/>
        <param name="endTime" value="30:00:00"/>
        <param name="flowCapacityFactor" value="1.0"/>
        <param name="storageCapacityFactor" value="1.0"/>
        <param name="numberOfThreads" value="4"/>
        <param name="mainMode" value="car"/>
    </module>
    <module name="scoring">
        <param name="learningRate" value="1.0"/>
        <param name="brainExpBeta" value="2.0"/>
        <parameterset type="scoringParameters">
            <param name="lateArrival" value="-18"/>
            <param name="earlyDeparture" value="-0"/>
            <param name="performing" value="+6"/>
            <param name="waiting" value="-0"/>
            <parameterset type="modeParams">
                <param name="mode" value="car"/>
                <param name="marginalUtilityOfTraveling_util_hr" value="-6.0"/>
            </parameterset>
            <parameterset type="modeParams">
                <param name="mode" value="pt"/>
            </parameterset>
            <parameterset type="modeParams">
                <param name="mode" value="walk"/>
            </parameterset>
            <parameterset type="activityParams">
                <param name="activityType" value="home"/>
                <param name="typicalDuration" value="12:00:00"/>
            </parameterset>
            <parameterset type="activityParams">
                <param name="activityType" value="work"/>
                <param name="typicalDuration" value="08:00:00"/>
            </parameterset>
        </parameterset>
    </module>
    <module name="replanning">
        <param name="maxAgentPlanMemorySize" value="3"/>
        <parameterset type="strategysettings">
            <param name="strategyName" value="ChangeExpBeta"/>
            <param name="weight" value="0.8"/>
        </parameterset>
        <parameterset type="strategysettings">
            <param name="strategyName" value="ReRoute"/>
            <param name="weight" value="0.2"/>
        </parameterset>
    </module>
</config>
EOF

echo "OK: MATSim inputs in $MATSIM_DIR (iters=${ITERS})"
echo "Run MATSim, then export demand for SUMO:"
echo "  mkdir -p $MATSIM_DIR/output"
echo "  docker run --rm \\"
echo "    -v $MATSIM_DIR:/matsim/input:ro \\"
echo "    -v $MATSIM_DIR/output:/matsim/output \\"
echo "    -e MATSIM_CONFIG=/matsim/input/config.xml \\"
echo "    -e MATSIM_HEAP=4g \\"
echo "    $MATSIM_IMAGE"
echo "  $ROOT/base/scripts/export_matsim_demand.sh $MATSIM_DIR/output/output_plans.xml.gz"
