#Importar paquetes
using Random, Distributions, Plots
using DataFrames, CSV
using JuMP , HiGHS      # https://jump.dev/JuMP.jl/stable/manual/models/ 
using Gurobi
using XLSX  # Se agrega para leer archivos .xlsx (Excel)

Random.seed!(1234) #para que las simulaciones de prueba sean consistentes

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
#println(renewables)

# inicio simulaciones
iteraciones = 100
min_k_wind = 14.70
max_k_wind = 30.92
min_k_sun = 10.20
max_k_sun = 14.02
sim_wind = []
sim_sun = []
sim_sis = [] 

# 40 eolicas 20 solares
for k in 1:iteraciones
    forecasts = zeros(60,24)
    wind_tot = zeros(1,24)
    sun_tot = zeros(1,24)
    #println(forecasts)
    for i in 1:60 
        for j in 1:24
            #println(renewables[i,1+j] )
            mu = renewables[i,1+j]     #acá tomar valor del excel
            if (i<=40)   #acá incluir si es solar o eólica
                m=(max_k_wind-min_k_wind)/(24-1)/100
                sigma = mu*(j*m+min_k_wind/100-m)
                #println(j*m+min_k_wind/100-m)
            else
                m=(max_k_sun-min_k_sun)/(24-1)/100
                sigma = mu*(j*m+min_k_sun/100-m)
                #println(j*m+min_k_sun/100-m)
            end
            sim_norm = mu + rand(Normal(0,sigma)) #   Eventualmente se podría borrar la aproximación
            if (sim_norm<0)         #trunca valores negativos
                forecasts[i,j] = 0 
            else
            forecasts[i,j] = sim_norm
            end
            if (i<=40)
                wind_tot[j]+=sim_norm
            else
                sun_tot[j]+=sim_norm
            end       
        end
    end 
    #forecasts
    append!(sim_wind,wind_tot)
    #sun_tot
    #ren_tot = sun_tot + wind_tot

end
horas = 1:24
#plot!(horas, wind_tot, title="Predicciones eolicas")