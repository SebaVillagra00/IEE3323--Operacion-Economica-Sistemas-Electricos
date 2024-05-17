# Tarea 2 Operacion Economica de Sistemas Electricos
# Vicente Goehring & Sebastian Villagra
# Mayo 2024

# Codigo busca crear un modelo de optimizacion para el Unit Commitment
# de forma mas general posible, i.e., entra como input cualquier CSV con
# los datos de un sistema y optimiza de forma robusta.


#Iniciación de paquetes
using DataFrames, CSV
using JuMP , HiGHS      # https://jump.dev/JuMP.jl/stable/manual/models/ 
using Gurobi
using XLSX  # Se agrega para leer archivos .xlsx (Excel)

#Definición de struct: FALTA AGREGAR MAS INSTANCIAS DE CADA STRUCT (seba)  
# Generadores
struct Gen
    Id::Int64
    PotMin::Int64
    PotMax::Int64
    Cost::Int64
    Ramp::Int64 
    Barra::Int64
end
# Potencias demandadas
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
# Lineas de transmision
struct Linea
    Id::Int64
    Inicio::Int64   # Barra de Inicio
    Fin::Int64      # Barra de Fin
    PotMax::Int64   # Potencia maxima a transportrat
    Imp::Float64 
end
# Battery Energy Storage System
struct BESS
    Id::Int64
    PotMax::Int64
    Duration::Int64
    Eff::Float64
    Estart::Float64
    Efinal::Float64
    Barra::Int64
end

##  Archivo Excel a leer
archivo = "Case014.xlsx"    # se comienza con el caso mas pequeño
xf = XLSX.readxlsx(archivo) # leer el archivo excel

# Separar hojas del archivo
buses = xf["Buses"]
demandas = xf["Demand"]
generadores = xf["Generators"]
lineas = xf["Lines"]
renovables = xf["Renewables"]

# Definir la función de parada
# Se crea el DataFrame hasta que se reconozca la entrada "END"
# De esta forma se puede leer tablas con cualquier numero de filas
#   siempre y cuando terminen con un "END".
function stop_condition(row)
    return isempty(row[1]) || row[1] == "END"
end

# Crear DataFrames
# XLSX.gettable(objeto hoja excel, Columnas de tabla, first_row= primera fila a considerar, stop_in_row_function: condicion dejar de leer)
buses_ref       = DataFrame(XLSX.gettable(buses,"A:E",first_row=1,stop_in_row_function=stop_condition))
demandaP_ref    = DataFrame(XLSX.gettable(demandas,"A:Y",first_row=2,stop_in_row_function=stop_condition))
demandaQ_ref    = DataFrame(XLSX.gettable(demandas,"AA:AY",first_row=2,stop_in_row_function=stop_condition))
generadores_ref = DataFrame(XLSX.gettable(generadores,"A:T",first_row=1,stop_in_row_function=stop_condition))
lineas_ref      = DataFrame(XLSX.gettable(lineas,"A:G",first_row=1,stop_in_row_function=stop_condition))
renovables_ref  = DataFrame(XLSX.gettable(renovables,"A:Y",first_row=2,stop_in_row_function=stop_condition))
# Notar que se crean 2 DataFrame a partir de la hoja "Demand": Potencia activa (P) y potencia reactiva (Q).
# Ademas, la fila considerada como inicio de la tabla es la fila 2, ya que la fila 1 solo hace distincion entre estas 2 potencias.
# Lo mismo ocurre en el DataFrame "renovables_ref".

# ESTO SE ELIMINARIA
#######################################################
#Importación de archivos
#generators_ref  = CSV.File("Generators.csv") |> DataFrame   # Crear DataFrame generadores
#demand_ref      = CSV.File("Demand.csv") |> DataFrame       # Crear DataFrame demanda
#lines_ref       = CSV.File("Lines.csv") |> DataFrame        # Crear DataFrame lineas tx
#batteries_ref   = CSV.File("Bess.csv") |> DataFrame         # Crear DataFrame baterias
# Crear una copia 
#generators      = copy(generators_ref)
#demand          = copy(demand_ref)
#lines           = copy(lines_ref)
#batteries       = copy(batteries_ref)
#######################################################

# Crear copias
buses = copy(buses_ref)
demandP = copy(demandaP_ref)
demandQ = copy(demandaQ_ref)
generators = copy(generadores_ref)
lines = copy(lineas_ref)
renewables = copy(renovables_ref) 

#inclusión en variables
P_base = 100
T = ncol(demandP)-1      # N° bloques temporales
N = nrow(buses)        # N° nodos 
I = nrow(generators)    # N° Generadores
L = nrow(lines)         # N° Lineas
#B = nrow(batteries)     # N° BESS

# Debugg check
println("Prueba de numero buses, deberia ser 14: ", N)

# HASTA ACA LLEGUE (SEA -quien mas xdxdxdxd): 17/05 -

# Listas que almacenan los Structs 
Generadores = []
Demandas    = []
Lineas      = []
#Baterias    = []

## Crear los Structs
# Struct Generadores
for i in 1:I
    x = Gen(generators[i,1],generators[i,2],generators[i,3],generators[i,4],generators[i,5],generators[i,6])
    push!(Generadores, x)
end
## println(Generadores[1].PotMax) ejemplo de como obtener un prámetro en particular

for i in 1:L
    x = Linea(lines[i,1],lines[i,2],lines[i,3],lines[i,4],lines[i,5])   # Esta linea crea el struct i
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