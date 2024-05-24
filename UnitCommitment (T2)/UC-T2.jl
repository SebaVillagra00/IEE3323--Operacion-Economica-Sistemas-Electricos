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

# Barras
struct Bus
    Id::Int64       # Id del Bus
    Vmax::Float64   # Voltaje maximo [pu]
    Vmin::Float64   # Voltaje minimo [pu]
    Gs::Float64
    Bs::Float64
end

# Generadores
struct Generador
    Name::String
    Bus::Int64    
    PotMax::Float64
    PotMin::Float64
    Qmax::Float64
    Qmin::Float64
    Ramp::Int64
    Sramp::Int64
    MinUp::Int64
    MinDn::Int64
    InitS::Int64
    InitP::Int64
    StartCost::Int64
    FixedCost::Int64
    VariableCost::Int64
    Type::String
    PminFactor::Float64 
    Qfactor::Float64
    RampFactor::Float64
    StartUpCostFactor::Int64
end
# Potencias demandadas
# La demanda la dejaria como un DataFrame y listo
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
# IMPORTANTE:   case014.xlsx tiene el inicio y fin como string. case118.xlsx los tiene como int
#               Por lo tanto, se modifica el archivo case014.xlsx para poder leer de forma automatica
struct Linea
    Name::String    
    Inicio::Int64       # Barra de Inicio
    Fin::Int64          # Barra de Fin
    R::Float64          # Resistencia
    X::Float64          # Reactancia
    LineCharging::Int64 # (B)
    PotMax::Int64       # Potencia maxima a transportar
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
# Renewables -> tambien dejarlo como DataFrame

##  Archivo Excel a leer
archivo = "Case014.xlsx"    # se comienza con el caso mas pequeño
xf = XLSX.readxlsx(archivo) # leer el archivo excel

# Separar hojas del archivo
sheet_buses = xf["Buses"]
sheet_demandas = xf["Demand"]
sheet_generadores = xf["Generators"]
sheet_lineas = xf["Lines"]
sheet_renovables = xf["Renewables"]

# Definir la función de parada
# Se crea el DataFrame hasta que se reconozca la entrada "END"
# De esta forma se puede leer tablas con cualquier numero de filas
#   siempre y cuando terminen con un "END".
function stop_condition(row)
    return isempty(row[1]) || row[1] == "END"
end

# Crear DataFrames
# XLSX.gettable(objeto hoja excel, Columnas de tabla, first_row= primera fila a considerar, stop_in_row_function: condicion dejar de leer)
buses_ref       = DataFrame(XLSX.gettable(sheet_buses,"A:E",first_row=1,stop_in_row_function=stop_condition))
demandaP_ref    = DataFrame(XLSX.gettable(sheet_demandas,"A:Y",first_row=2,stop_in_row_function=stop_condition))
demandaQ_ref    = DataFrame(XLSX.gettable(sheet_demandas,"AA:AY",first_row=2,stop_in_row_function=stop_condition))
generadores_ref = DataFrame(XLSX.gettable(sheet_generadores,"A:T",first_row=1,stop_in_row_function=stop_condition))
lineas_ref      = DataFrame(XLSX.gettable(sheet_lineas,"A:G",first_row=1,stop_in_row_function=stop_condition))
renovables_ref  = DataFrame(XLSX.gettable(sheet_renovables,"A:Y",first_row=2,stop_in_row_function=stop_condition))
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
T = ncol(demandP)-1         # N° bloques temporales
N = nrow(buses)             # N° nodos 
I = nrow(generators)        # N° Generadores
L = nrow(lines)             # N° Lineas
#B = nrow(batteries)        # N° BESS

# Debugg check
println("Prueba de numero buses, deberia ser 14: ", N)

# HASTA ACA LLEGUE (SEA -quien mas xdxdxdxd): 17/05 -

# Listas que almacenan los Structs 
Buses       = []
Gen         = []
Demandas    = []
Lineas      = []
#Baterias    = []


## Crear los Structs

# Struct Bus
# struct Bus
#     Id::Int64       # Id del Bus
#     Vmax::Float64   # Voltaje maximo [pu]
#     Vmin::Float64   # Voltaje minimo [pu]
#     Gs::Float64
#     Bs::Float64
# end
for i in 1:N
    x = Bus(
        lines[i,i], # 1- Id
        lines[i,2], # 2- Vmax [pu]
        lines[i,3], # 3- Vmin [pu]
        lines[i,4], # 4- Gs
        lines[i,5]) # 8- Bs   
    push!(Lineas, x)
end

# Struct Generadores
# struct Gen
#     (1)Id:: Int64              
#     (2)Name::String
#     (3)Bus::Int64    
#     (4)PotMax::Float64
#     (5)PotMin::Float64
#     (6)Qmax::Float64
#     (7)Qmin::Float64
#     (8)Ramp::Int64
#     (9)Sramp::Int64
#     (10)MinUp::Int64
#     (11)MinDn::Int64
#     (12)InitS::Int64
#     (13)InitP::Int64
#     (14)StartCost::Int64
#     (15)FixedCost::Int64
#     (16)VariableCost::Int64
#     (17)Type::String
#     (18)PminFactor::Float64 
#     (19)Qfactor::Float64
#     (20)RampFactor::Float64
#     (21)StartUpCostFactor::Int64
# end
for i in 1:I
    x = Generador(
        generators[i,1],    # 1- Name
        generators[i,2],    # 2- Bus
        generators[i,3],    # 3- Pmax
        generators[i,4],    # 4- Pmin
        generators[i,5],    # 5- Qmax
        generators[i,6],    # 6- Qmin
        generators[i,7],    # 7- Ramp [Mw/h]
        generators[i,8],    # 8- Sramp [Mw]
        generators[i,9],    # 9- MinUp
        generators[i,10],   # 10- MinDn
        generators[i,11],   # 11- InitS
        generators[i,12],   # 12- InitP
        generators[i,13],   # 13- StartCost
        generators[i,14],   # 14- FixedCost
        generators[i,15],   # 15- VariableCost
        generators[i,16],   # 16- Type
        generators[i,17],   # 17- PminFactor
        generators[i,18],   # 18- Qfactor
        generators[i,19],   # 19- RampFactor
        generators[i,20])   # 20- StartUpCostFactor
    push!(Generadores, x)
end
## println(Generadores[1].PotMax) ejemplo de como obtener un prámetro en particular

# Struct Linea
# struct Linea
#     Id::Int64
#     Name::String    
#     Inicio::Int64       # Barra de Inicio
#     Fin::Int64          # Barra de Fin
#     R::Float64          # Resistencia
#     X::Float64          # Reactancia
#     LineCharging::Int64 # (B)
#     PotMax::Int64       # Potencia maxima a transportar
# end
for i in 1:L
    x = Linea(
        lines[i,1], # 1- Name 
        lines[i,2], # 2- StartBus
        lines[i,3], # 3- EndBus
        lines[i,4], # 4- Resistance
        lines[i,5], # 5- Reactance
        lines[i,6], # 6- LineCharging(B)
        lines[i,7]) # 7- MaxFlow [Mw]   
    push!(Lineas, x)
end

# Struct demanda (quizas quitarlo)
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

# Variables Economic Dispatch
@variable(model, p[1:I, 1:T] >= 0)  # Potencia activa de generador i en tiempo t. Valor en p.u.
@variable(model, d[1:N, 1:T])       # angulo (d de degree) de la barra n en tiempo t

# Variables nuevas (UC)
# No se utiliza potencia reactiva: Aproximacion DC
#@variable(model, q[1:I, 1:T])       # Potencia reactiva de generador i en tiempo t. Valor en p.u. (puede ser < 0)
@variable(model, u[1:I, 1:T], Bin)       # AGREGAR NATURALEZA {0,1}. Indica encendido de gen i en t.
@variable(model, v[1:I, 1:T], Bin)       # AGREGAR NATURALEZA {0,1}. Indica apagado de gen i en t.
@variable(model, w[1:I, 1:T], Bin)       # AGREGAR NATURALEZA {0,1}. Estado ON(1)/OFF(0) de gen i en t.

# Variables BESS (no se utilizan)
#@variable(model, pb[1:B, 1:T])      # flujo de potencia del BESS b en tiempo t
#@variable(model, e[1:B,1:T] >=0)    # energia almacenada en el BESS e en tiempo t

## Funcion Objetivo
@objective(model, Min, sum(Gen[i].VariableCostCost * p[i,t] +  Gen[i].FixedCost * w[i,t] + Gen[i].StartCost * u[i,t] for i in 1:I, t in 1:T ))

### Restricciones

# Equilibrio de Potenica
#Flujo DC   
# IDEA: ahora los datos traen R y X. Agregaria Imp como atributo adicional al momento de generar cada
#       estructura LINEA. De esta forma se mantiene esta restriccion

# Demanda Potencia Activa
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


### Restricciones de generadores

## Potencias Activas y reactivas
# Potencia Activa maxima
@constraint(model, PMaxConstraint[i in 1:I, t in 1:T], p[i,t] <= w[i,t]*Gen[i].PotMax)
# Potencia Activa minima
@constraint(model, PMinConstraint[i in 1:I, t in 1:T], w[i,t]*Gen[i].PotMin <= p[i,t])

# Potencia Reactiva maxima
#@constraint(model, QMaxConstraint[i in 1:I, t in 1:T], q[i,t] <= Gen[i].QMax)
# Potencia Reactiva minima
#@constraint(model, QMinConstraint[i in 1:I, t in 1:T], Gen[i].QMin <= q[i,t])

############# actualizacion 22-05 (sea)
#               ARRIBA hay que modificar el equilibrio de demandas y saturacion de lineas

## Rampas
# Rampa up
@constraint(model, RampUpConstaint[i in 1:I, t in 2:T], (p[i,t] - p[i,t-1]) <= Gen[i].Ramp + Gen.Sramp[i]*u[i,t])
# Rampa dn
@constraint(model, RampDownConstaint[i in 1:I, t in 2:T], (p[i,t] - p[i,t-1]) >= -Generadores[i].Ramp - Gen.Sramp[i]*v[u,t])

## Estados Binarios
@constraint(model, BinaryState[i in 1:I, t in 2:T], (u[i,t] - v[i,t]) = (w[i,t] - w[i,t-1]))
#@constraint(model, BinaryInitial[i in 1:I], (w[i,1] = State0[i]))   # Condicion inicial, por ahora libre

## Tiempo minimo de encendido

## Tiempo minimo de apagado




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

#############################################################

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