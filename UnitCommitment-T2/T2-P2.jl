#Importar paquetes
using Random, Distributions, Plots
using DataFrames, CSV
using JuMP , HiGHS      # https://jump.dev/JuMP.jl/stable/manual/models/ 
using Gurobi
using XLSX  # Se agrega para leer archivos .xlsx (Excel)
#Lectura de excel
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
renovables_ref  = DataFrame(XLSX.gettable(sheet_renovables,"A:Y",first_row=2,stop_in_row_function=stop_condition))
renewables = copy(renovables_ref) 
println(renewables)

# inicio simulaciones
iteraciones = 100
min_k_wind = 14.70
max_k_wind = 30.92
min_k_sun = 10.20
max_k_sun = 14.02

# 40 eolicas 20 solares
forecasts = zeros(60,24)
#println(forecasts)
for i in 1:60 
    for j in 1:24
        #println(renewables[i,1+j] )
        mu = renewables[i,1+j]     #acá tomar valor del excel
        if (i<=40)   #acá incluir si es solar o eólica
            sigma = mu*j*(max_k_wind-min_k_wind)/(24-1)
        else
            sigma = mu*j*(max_k_sun-min_k_sun)/(24-1)
        end
        sim_norm = mu + rand(Normal(0,sigma)) #   Eventualmente se podría borrar la aproximación
        if (sim_norm<0)
            forecasts[i,j] = 0 
        else
        forecasts[i,j] = sim_norm 
        end      
    end
end   

#println(forecasts)
forecasts
