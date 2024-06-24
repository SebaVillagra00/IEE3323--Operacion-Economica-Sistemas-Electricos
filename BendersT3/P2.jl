#Paquetes
using SDDP
using HiGHS

#Se crea grafo
graph = SDDP.LinearGraph(3)

#Sub-Problema
function subproblem_builder(subproblem::Model, node::Int)
    # State variables
    @variable(subproblem, 0 <= volume <= 200, SDDP.State, initial_value = 200)
    # Control variables
    @variables(subproblem, begin
        thermal_generation >= 0
        hydro_generation >= 0
        hydro_spill >= 0
    end)
    # Random variables
    @variable(subproblem, inflow)
    Ω = [0.0, 50.0, 100.0]
    P = [1 / 3, 1 / 3, 1 / 3]
    SDDP.parameterize(subproblem, Ω, P) do ω
        return JuMP.fix(inflow, ω)
    end
    # Transition function and constraints
    @constraints(
        subproblem,
        begin
            volume.out == volume.in - hydro_generation - hydro_spill + inflow
            demand_constraint, hydro_generation + thermal_generation == 150
        end
    )
    # Stage-objective
    fuel_cost = [50, 100, 150]
    @stageobjective(subproblem, fuel_cost[node] * thermal_generation)
    return subproblem
end

model = SDDP.PolicyGraph(
    subproblem_builder,
    graph;
    sense = :Min,
    lower_bound = 0.0,
    optimizer = HiGHS.Optimizer,
)

SDDP.train(model; iteration_limit = 10)