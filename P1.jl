# Tarea 1 Operacion Economica de Sistemas Electricos
# Vicente Goehring & Sebastian Villagra
# Abril 2024

# Codigo busca crear un modelo de optimizacion para el despacho economico
# de forma mas general posible, i.e., entra como input cualquier CSV con
# los datos de un sistema y optimiza de forma robusta.


#Iniciación de paquetes
using DataFrames, CSV
using JuMP , HiGHS      # https://jump.dev/JuMP.jl/stable/manual/models/ 
using Gurobi

#Definición de struct   
#Hay que ver bien como usarlas

struct Gen
    Id::Int64
    PotMin::Int64
    PotMax::Int64
    Cost::Int64
    Ramp::Int64 
    Barra::Int64
end
struct Demanda
    Barra::Int64
    T1::Int64
    T2::Int64
    T3::Int64
    T4::Int64
    T5::Int64
    T6::Int64
end
struct Linea
    Id::Int64
    Inicio::Int64
    Fin::Int64
    PotMax::Int64
    Imp::Float64 
end

#Importación de archivos
generators_ref  = CSV.File("Generators.csv") |> DataFrame
demand_ref      = CSV.File("Demand.csv") |> DataFrame
lines_ref       = CSV.File("Lines.csv") |> DataFrame
generators      = copy(generators_ref)
demand          = copy(demand_ref)
lines           = copy(lines_ref)


#inclusión en variables
Generadores = []
Demandas    = []
Lineas      = []

for i in 1:nrow(generators)
    x = Gen(generators[i,1],generators[i,2],generators[i,3],generators[i,4],generators[i,5],generators[i,6])
    push!(Generadores, x)
end
## println(Generadores[1].PotMax) ejemplo de como obtener un prámetro en particular

for i in 1:nrow(lines)
    x = Linea(lines[i,1],lines[i,2],lines[i,3],lines[i,4],lines[i,5])
    push!(Lineas, x)
end

for i in 1:nrow(demand)
    x = Demanda(demand[i,1],demand[i,2],demand[i,3],demand[i,4],demand[i,5],demand[i,6],demand[i,7])
    push!(Demandas, x)
end
println(Lineas[4].Imp)


## Matriz Admitancia

## IMPORTANTE: ARRIBA HAY QUE DEFINIR N,T e I.
P_base = 100
T = ncol(demand)-1
N = nrow(demand)
I = nrow(generators)

### Problema optimizacion
m = Model(Gurobi.Optimizer) # Crear objeto "modelo" con el solver Gurobi

## Variables
@variable(model, p[1:I, 1:T] >= 0)  # potencia de generador i en tiempo t
@variable(model, d[1:N, 1:T])       # angulo (d de degree) de la barra n en tiempo t

## Funcion Objetivo
@objective(model, Min, sum(Generadores[i].Cost * p[i,t] for i in 1:I, t in 1:T ))

## Restricciones
# Equilibrio de Potenica
@constraint(model, c1, restriccion matematica)



#Restricciones de generadores
# Potencia maxima
@constraint(model, PMaxConstraint[i in 1:I, t in 1:T], p[i,t] <= Generadores[i].PotMax)
# Potencia minima
@constraint(model, PMinConstraint[i in 1:I, t in 1:T], Generadores[i].PotMin<= p[i,t])
# Rampa up
@constraint(model, RampUpConstaint[i in 1:I, t in 2:T], p[i,t] - p[i,t-1] <= Generadores[i].Ramp)
# Rampa dn
@constraint(model, RampDownConstaint[i in 1:I, t in 2:T], p[i,t] - p[i,t-1] >= -Generadores[i].Ramp)