#Iniciación de paquetes
using DataFrames, CSV
using JuMP , HiGHS

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