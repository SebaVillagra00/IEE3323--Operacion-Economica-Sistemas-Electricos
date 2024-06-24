#Paquetes
using SDDP
using HiGHS
using Random

#Se incluye semilla para que las simulaciones sean consistentes
Random.seed!(1234)

#Se crea grafo
graph = SDDP.LinearGraph(100)

#Sub-Problema
function subproblem_builder(subproblem::Model, node::Int)
    # State variables
    @variable(subproblem, 0 <= volume <= 300, SDDP.State, initial_value = 100)
    # Control variables
    @variables(subproblem, begin
        0 <= G1 <= 50
        0 <= G2 <= 50
        0 <= G3 <= 50
        0 <= hydro_generation <= 150
        hydro_spill == 0         # Se fija como 0
    end)
    # Random variables
    @variable(subproblem, inflow)
    Ω = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]
    
    P = [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
    SDDP.parameterize(subproblem, Ω, P) do ω
        return JuMP.fix(inflow, ω)
    end
    # Transition function and constraints
    @constraints(
        subproblem,
        begin
            volume.out == volume.in - hydro_generation - hydro_spill + inflow
            demand_constraint, hydro_generation + G1 + G2 + G3 == 150 
        end
    )
    # Stage-objective
    fuel_cost = [50, 100, 150]
    @stageobjective(subproblem, fuel_cost[1] * G1 + fuel_cost[2] * G2 + fuel_cost[3] * G3)
    return subproblem
end

model = SDDP.PolicyGraph(
    subproblem_builder,
    graph;
    sense = :Min,
    lower_bound = 0.0,
    optimizer = HiGHS.Optimizer,
)

SDDP.train(model; iteration_limit = 20)      #Acá se debe cambiar entre 5, 20, 50 y 100 iteraciones



println("Ahora con 100 simulaciones")
simulations = SDDP.simulate(
    # The trained model to simulate.
    model,
    # The number of replications.
    100,
    # A list of names to record the values of.
    [:volume, :G1, :G2, :G3, :hydro_generation, :hydro_spill],
)
#Muestra el volumen almacenado al final de cada semana
println("El volumen almacenado al final de cada semana es: ")
outgoing_volume = map(simulations[1]) do node
    return println(node[:volume].out)
end

objectives = map(simulations) do simulation
    return sum(stage[:stage_objective] for stage in simulation)
end
#=
#interavlos de confianza
#El valor default es del 95%
println("Intervalos de confianza")
μ1, ci1 = SDDP.confidence_interval(objectives)
println("Confidence interval: ", μ1, " ± ", ci1)
println("Cota inferior: ", SDDP.calculate_bound(model))
=#
#costos marginales del agua para la primera etapa

V = SDDP.ValueFunction(model; node = 1)
cost1, price1 = SDDP.evaluate(V, Dict("volume" => 10))
println("Costos futuros  del agua almacenada para primera etapa es :", cost1)
println("Costos marginales del agua almacenada para primera etapa es :", price1)


println("Ahora con más simulaciones (2000)")
simulations2 = SDDP.simulate(
    # The trained model to simulate.
    model,
    # The number of replications.
    2000,
    # A list of names to record the values of.
    [:volume, :G1, :G2, :G3, :hydro_generation, :hydro_spill],
)
#=
#Muestra el volumen almacenado al final de cada semana
println("El volumen almacenado al final de cada semana es: ")
outgoing_volume = map(simulations2[1]) do node
    return println(node[:volume].out)
end
=#

objectives2 = map(simulations2) do simulation
    return sum(stage[:stage_objective] for stage in simulation)
end

#interavlos de confianza
#El valor default es del 95%
println("Intervalos de confianza")
μ2, ci2 = SDDP.confidence_interval(objectives2)
println("Confidence interval: ", μ2, " ± ", ci2)
println("Cota inferior: ", SDDP.calculate_bound(model))

#costos marginales del agua para la primera etapa
println("Costos futuros y costos marginales del agua almacenada para primera etapa:")
V = SDDP.ValueFunction(model; node = 1)
cost2, price2 = SDDP.evaluate(V, Dict("volume" => 10))
println("Costos futuros  del agua almacenada para primera etapa es :", cost2)
println("Costos marginales del agua almacenada para primera etapa es :", price2)