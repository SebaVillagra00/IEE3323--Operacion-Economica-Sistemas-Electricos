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
    T::Int64
    Barra1::Int64
    Barra2::Int64
    Barra3::Int64
    Barra4::Int64
    Barra5::Int64
    Barra6::Int64
    Barra7::Int64
    Barra8::Int64
    Barra9::Int64
end
struct Linea
    Id::Int64
    Inicio::Int64
    Fin::Int64
    PotMax::Int64
    Imp::Float64 
end
struct BESS
    Id::Int64
    PotMax::Int64
    Duration::Int64
    Eff::Float64
    Estart::Float64
    Efinal::Float64
    Barra::Int64
end

#Importación de archivos
generators_ref  = CSV.File("Generators.csv") |> DataFrame   # Crear DataFrame generadores
demand_ref      = CSV.File("Demand.csv") |> DataFrame       # Crear DataFrame demanda
lines_ref       = CSV.File("Lines.csv") |> DataFrame        # Crear DataFrame lineas tx
batteries_ref   = CSV.File("Bess.csv") |> DataFrame         # Crear DataFrame baterias
# Crear una copia 
generators      = copy(generators_ref)
demand          = copy(demand_ref)
lines           = copy(lines_ref)
batteries       = copy(batteries_ref)

#inclusión en variables
P_base = 100
T = ncol(demand)-1      # N° bloques temporales
N = nrow(demand)        # N° nodos 
I = nrow(generators)    # N° Generadores
L = nrow(lines)         # N° Lineas
B = nrow(batteries)     # N° BESS

println("Prueba de numero baterias, deberia ser 3: ", B)

# Listas que almacenan los Structs 
Generadores = []
Demandas    = []
Lineas      = []
Baterias    = []

for i in 1:I
    x = Gen(generators[i,1],generators[i,2],generators[i,3],generators[i,4],generators[i,5],generators[i,6])
    push!(Generadores, x)
end
## println(Generadores[1].PotMax) ejemplo de como obtener un prámetro en particular

for i in 1:L
    x = Linea(lines[i,1],lines[i,2],lines[i,3],lines[i,4],lines[i,5])
    push!(Lineas, x)
end

for i in 1:N
    x = [demand[i,2],demand[i,3],demand[i,4],demand[i,5],demand[i,6],demand[i,7]]
    push!(Demandas, x)
end
#println(Lineas[4].Imp)

# Crear Structs BESS
for b in 1:B
    x = BESS(batteries[b,1],batteries[b,2],batteries[b,3],batteries[b,4],
            batteries[b,5],batteries[b,6],batteries[b,7])
    push!(Baterias, x)
end

### Problema optimizacion
model = Model(Gurobi.Optimizer) # Crear objeto "modelo" con el solver Gurobi

## Variables
@variable(model, p[1:I, 1:T] >= 0)  # potencia de generador i en tiempo t. Valor en p.u.
@variable(model, d[1:N, 1:T])       # angulo (d de degree) de la barra n en tiempo t
@variable(model, pb[1:B, 1:T])      # flujo de potencia del BESS b en tiempo t
@variable(model, e[1:B,1:T] >=0)        # energia almacenada en el BESS e en tiempo t

## Funcion Objetivo
@objective(model, Min, sum(Generadores[i].Cost * p[i,t] for i in 1:I, t in 1:T ))

## Restricciones
# Equilibrio de Potenica
#Flujo DC
@constraint(model, DCPowerFlowConstraint[n in 1:N, t in 1:T], 
sum(p[i,t] for i in 1:I if Generadores[i].Barra == n) - Demandas[n][t]  
+ sum(pb[b,t] for b in 1:B if Baterias[b].Barra == n)    == 
P_base*sum( (1/Lineas[l].Imp) * (d[Lineas[l].Inicio,t] - d[Lineas[l].Fin,t]) for l in 1:L if Lineas[l].Inicio == n)
+ P_base*sum( (1/Lineas[l].Imp) * (d[Lineas[l].Fin,t] - d[Lineas[l].Inicio,t]) for l in 1:L if Lineas[l].Fin == n))
#Flujo en lineas. Se considera o de origen, y d de destino
@constraint(model, LineMaxPotInicioFin[l in 1:L, t in 1:T], 1/Lineas[l].Imp * (d[Lineas[l].Inicio,t] - d[Lineas[l].Fin,t]) <= Lineas[l].PotMax/P_base) 
@constraint(model, LineMinPotFinInicio[l in 1:L, t in 1:T], -1/Lineas[l].Imp * (d[Lineas[l].Inicio,t] - d[Lineas[l].Fin,t]) <= Lineas[l].PotMax/P_base)
#Angulo de referencia
@constraint(model, RefDeg[1, t in 1:T], d[1,t] == 0)  


#Restricciones de generadores
# Potencia maxima
@constraint(model, PMaxConstraint[i in 1:I, t in 1:T], p[i,t] <= Generadores[i].PotMax)
# Potencia minima
@constraint(model, PMinConstraint[i in 1:I, t in 1:T], Generadores[i].PotMin <= p[i,t])
# Rampa up
@constraint(model, RampUpConstaint[i in 1:I, t in 2:T], (p[i,t] - p[i,t-1]) <= Generadores[i].Ramp)
# Rampa dn
@constraint(model, RampDownConstaint[i in 1:I, t in 2:T], (p[i,t] - p[i,t-1]) >= -Generadores[i].Ramp)

# Restricciones de BESS
# Energia maxima
@constraint(model, EnergyMax[b in 1:B, t in 1:T], e[b,t] <= (Baterias[b].PotMax)*(Baterias[b].Duration))
# Potencia maxima descarga
@constraint(model, PMaxBessDischarge[b in 1:B, t in 1:T], pb[b,t] <= Baterias[b].PotMax)
# Potencia maxima carga
@constraint(model, PMaxBessCharge[b in 1:B, t in 1:T], pb[b,t] >= -1*(Baterias[b].PotMax))
# Imposibilidad de generacion - E inicial
@constraint(model, Estart[b in 1:B], e[b,1] == (Baterias[b].Estart)*(Baterias[b].PotMax)*(Baterias[b].Duration))
# Imposibilidad de generacion - E final
@constraint(model, Efinal[b in 1:B], e[b,T] == (Baterias[b].Efinal)*(Baterias[b].PotMax)*(Baterias[b].Duration))
# Dinamica BESS
@constraint(model, DynamicBESS[b in 1:B, t in 2:T], e[b,t] == e[b,t-1] - pb[b,t])


#RESULATDOS


#Valores de potencia de cada generador
JuMP.optimize!(model)
for t in 1:T
    println("Generación en T=", t," es para la unidad 1: ", JuMP.value(p[1,t])," para la unidad 2: ", JuMP.value(p[2,t]), " y para la unidad 3: ", JuMP.value(p[3,t]))
end
println("Dando un costo total de Operacion de: ", JuMP.objective_value(model))

#Valores de potencia de cada BESS -> Se podria meter a una funcion 
for t in 1:T
    println("Generación en T=", t," es para BESS 1: ", JuMP.value(pb[1,t])," para BESS 2: ", JuMP.value(pb[2,t]), " y para BESS 3: ", JuMP.value(pb[3,t]))
end

#Valores de energia de cada BESS
for t in 1:T
    println("Energia en T=", t," es para BESS 1: ", JuMP.value(e[1,t])," para BESS 2: ", JuMP.value(e[2,t]), " y para BESS 3: ", JuMP.value(e[3,t]))
end
println("Dando un costo total de Operacion de: ", JuMP.objective_value(model))



#Comparación resultados
#Se hace para comprobar que generacion=demanda
println("Comparación solución")
for t in 1:T
    println(JuMP.value(p[1,t]) + JuMP.value(p[2,t]) + JuMP.value(p[3,t]) +
            JuMP.value(pb[1,t]) + JuMP.value(pb[2,t]) + JuMP.value(pb[3,t])
            ," = ", Demandas[1][t]+Demandas[2][t]+Demandas[3][t]+Demandas[4][t]+
            Demandas[5][t]+Demandas[6][t]+Demandas[7][t]+Demandas[8][t]+Demandas[9][t])
end

#Costos marginales
println("Costos marginales de cada nodo")
for n in 1:N
    for t in 1:T
        print("Costo marginal en nodo ", n, " en peridodo ", t, ": ")
        println(JuMP.dual(DCPowerFlowConstraint[n,t]))
    end
end