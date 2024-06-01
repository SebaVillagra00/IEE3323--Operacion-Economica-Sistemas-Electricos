#Importar paquetes
using Random, Distributions, Plots
using DataFrames, CSV
using JuMP , HiGHS      # https://jump.dev/JuMP.jl/stable/manual/models/ 
using Gurobi
using XLSX  # Se agrega para leer archivos .xlsx (Excel)


Random.seed!(1234) #para que las simulaciones de prueba sean consistentes

#Definición de struct: 

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
    Ramp::Float64
    Sramp::Float64
    MinUp::Float64
    MinDn::Float64
    InitS::Float64
    InitP::Float64
    StartCost::Float64
    FixedCost::Float64
    VariableCost::Float64
    Tech::String
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
archivo = "Case118.xlsx"    # se comienza con el caso mas pequeño
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

# Crear copias (aparentemente buena practica)
global buses = copy(buses_ref)
global demandP = copy(demandaP_ref[:,2:25])
global demandQ = copy(demandaQ_ref)
global generators = copy(generadores_ref)
global lines = copy(lineas_ref)
global renewables = copy(renovables_ref) 

#inclusión en variables
P_base = 100
T = ncol(demandP)           # N° bloques temporales
N = nrow(buses)             # N° nodos 
I = nrow(generators)        # N° Generadores
L = nrow(lines)             # N° Lineas
R = nrow(renewables)        # N° Renovables

# Debugg check
#println("Prueba de numero buses, deberia ser 14: ", N)


# Listas que almacenan los Structs 
Buses       = []
Gen         = []
Demandas    = []
Lineas      = []

## Crear los Structs

# Struct Bus

for i in 1:N
    x = Bus(
        buses[i,1], # 1- Id
        buses[i,2], # 2- Vmax [pu]
        buses[i,3], # 3- Vmin [pu]
        buses[i,4], # 4- Gs
        buses[i,5]) # 8- Bs   
    push!(Buses, x)
end

# Struct Generadores


for i in 1:I
    #println("Generador", i)
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
    push!(Gen, x)
end
## println(Generadores[1].PotMax) ejemplo de como obtener un prámetro en particular

# Struct Linea

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




# inicio simulaciones
min_k_wind = 14.70 / 100
max_k_wind = 30.92 / 100
min_k_sun = 10.20 / 100
max_k_sun = 14.02 / 100



#Cada uno de estos vectores incluye los 100 escenarios para una hora dada

forecasts = zeros(60,24,100)  

for e in 1:100    
    for t in 1:24
        for g in 1:60
            mu = renewables[g,t+1]                      #acá toma valor del excel
            if (g<=40)                                  #acá revisa si es solar o eólica
                me=(max_k_wind-min_k_wind)/(24-1)
                sigma = mu*(t*me+min_k_wind-me)
            else
                ms=(max_k_sun-min_k_sun)/(24-1)
                sigma = mu*(t*ms+min_k_sun-ms)
            end
            sim_norm = mu + rand(Normal(0,sigma))       
            if (sim_norm<0)                             #trunca valores negativos
                sim_norm = 0
            end            
            forecasts[g,t,e] = Float64.(sim_norm )
        end        
    end
end

#println(forecasts[1,1,1])




# Struct demanda (quizas quitarlo)
# for i in 1:N
#     x = [demand[i,2],demand[i,3],demand[i,4],demand[i,5],demand[i,6],demand[i,7]]
#     push!(Demandas, x)
# end


####################################################################
#               MODELO OPTIMIZACION
####################################################################
## Estados Binarios
##  Archivo Excel a leer
archivo1 = "ResultadosCASE118-RES-90.xlsx"    # se comienza con el caso mas pequeño
xf1 = XLSX.readxlsx(archivo1) # leer el archivo excel

# Separar hojas del archivo
sheet_encendido = xf1["Encendido"]
sheet_apagado = xf1["Apagado"]
sheet_estados = xf1["State"]

function stop_condition(row)
    return isempty(row[1]) || row[1] == "END"
end

# Crear DataFrames
# XLSX.gettable(objeto hoja excel, Columnas de tabla, first_row= primera fila a considerar, stop_in_row_function: condicion dejar de leer)
ON_ref       = DataFrame(XLSX.gettable(sheet_encendido,"A:X",first_row=1,stop_in_row_function=stop_condition))
OFF_ref    = DataFrame(XLSX.gettable(sheet_apagado,"A:X",first_row=1,stop_in_row_function=stop_condition))
Estado_ref    = DataFrame(XLSX.gettable(sheet_estados,"A:X",first_row=1,stop_in_row_function=stop_condition))
# Crear copias (aparentemente buena practica)
global ON = copy(ON_ref)
global OFF = copy(OFF_ref)
global Estado = copy(Estado_ref)


es_factible = 0
suma_objetivos = 0
#se fijan los valores de encendido y apagado:
for E in 1:100
    # Potencia Renewables (condicionado a meteorologia)
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


    ## Funcion Objetivo
    @objective(model, Min, sum(Gen[i].VariableCost * p[i,t] +  Gen[i].FixedCost * w[i,t] + Gen[i].StartCost * u[i,t] for i in 1:I, t in 1:T ))

    ### Restricciones

    # Equilibrio de Potenica (APROXIMACION: Flujo DC  --> Demanda Potencia Activa)
    @constraint(model, DCPowerFlowConstraint[n in 1:N, t in 1:T], 
    sum(p[i,t] for i in 1:I if Gen[i].Bus == n) - demandP[n,t]      == 
    P_base*sum( (1/Lineas[l].X) * (d[Lineas[l].Inicio,t] - d[Lineas[l].Fin,t]) for l in 1:L if Lineas[l].Inicio == n)
    + P_base*sum( (1/Lineas[l].X) * (d[Lineas[l].Fin,t] - d[Lineas[l].Inicio,t]) for l in 1:L if Lineas[l].Fin == n))

    # + sum(pb[b,t] for b in 1:B if Baterias[b].Barra == n) | Al lado izquierdo de la ecuación (baterias)

    #Flujo en lineas. Se considera o de origen, y d de destino
    @constraint(model, LineMaxPotInicioFin[l in 1:L, t in 1:T], 1/Lineas[l].X * (d[Lineas[l].Inicio,t] - d[Lineas[l].Fin,t]) <= Lineas[l].PotMax/P_base) 
    @constraint(model, LineMinPotFinInicio[l in 1:L, t in 1:T], -1/Lineas[l].X * (d[Lineas[l].Inicio,t] - d[Lineas[l].Fin,t]) <= Lineas[l].PotMax/P_base)
    #Angulo de referencia
    @constraint(model, RefDeg[1, t in 1:T], d[1,t] == 0)  

    ### Restricciones de generadores

    ## Potencias Activas y reactivas
    # Potencia Activa maxima
    @constraint(model, PMaxConstraint[i in 1:I, t in 1:T], p[i,t] <= w[i,t]*Gen[i].PotMax)
    # Potencia Activa minima
    @constraint(model, PMinConstraint[i in 1:I, t in 1:T], w[i,t]*Gen[i].PotMin <= p[i,t])


    ## Rampas
    # Rampa up
    @constraint(model, RampUpConstaint[i in 1:I, t in 2:T], (p[i,t] - p[i,t-1]) <= Gen[i].Ramp + Gen[i].Sramp*u[i,t])
    # Rampa dn
    @constraint(model, RampDownConstaint[i in 1:I, t in 2:T], (p[i,t] - p[i,t-1]) >= 0-Gen[i].Ramp - Gen[i].Sramp*v[i,t])

    ## Tiempo minimo de encendido: sumo todos los x dentro de la ventana desde t=1 hasta el instante enterior al encendido
    @constraint(model, MinUpTime[i in 1:I, t in 2:T], sum(w[i,k] for k in 1:(t-1) if k >= t-Gen[i].MinUp) >= v[i,t]*Gen[i].MinUp)
    ## Tiempo minimo de apagado
    @constraint(model, MinDnTime[i in 1:I, t in 2:T], sum((1-w[i,k]) for k in 1:(t-1) if k >= t-Gen[i].MinDn) >= u[i,t]*Gen[i].MinDn)


    

    #@constraint(model, BinaryState[i in 1:I, t in 2:T], (u[i,t] - v[i,t]) == (w[i,t] - w[i,t-1]))
    @constraint(model, BinaryStateW[i in 1:I, t in 1:T], u[i,t] == ON[i,t])
    @constraint(model, BinaryStateV[i in 1:I, t in 1:T], v[i,t] == OFF[i,t])
    @constraint(model, BinaryStateU[i in 1:I, t in 1:T], w[i,t] == Estado[i,t])


    @constraint(model, RenewableMax[i in (I-R+1):I, t in 1:T], p[i,t] <= forecasts[i-(I-R),t,E])
    JuMP.optimize!(model)
    if (termination_status(model) == MOI.OPTIMAL)
        global es_factible += 1        
        global suma_objetivos += objective_value(model)
    end
end

println("Probabilidad de requerimiento de load shedding y renewable curtailment = ",(1-es_factible/100)*100,"%")
println("Promedio de costos ", suma_objetivos/es_factible)


#    COSTOS
#=
totalCost = objective_value(model)
fixCost = zeros(Float64, (I,T))     # fijo
varCost = zeros(Float64, (I,T))     # variable
startCost = zeros(Float64, (I,T))   # encendido
=#