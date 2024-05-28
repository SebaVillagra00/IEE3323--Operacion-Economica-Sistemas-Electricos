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
for _ in 1:100
    push!(sim_wind, 0)
    push!(sim_sun, 0)
    push!(sim_sis, 0)
end
println(sim_wind)

# 40 eolicas 20 solares
for k in 1:iteraciones
    forecasts = [] # zeros(60,24)
    f_wind = [] # zeros(1,24)
    f_sun = [] # zeros(1,24)
    wind_tot = [] # zeros(1,24)
    sun_tot = [] # zeros(1,24)
    for _ in 1:60
        push!(forecasts, 0)
    end
    for _ in 1:24
        push!(f_wind, 0)
        push!(f_sun, 0)
        push!(wind_tot, 0)
        push!(sun_tot, 0)
    end
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
                #forecasts[i,j] = 0 
                sim_norm = 0
            #else
            #forecasts[i,j] = sim_norm
            end
            if (i<=40)
                f_wind[j] = sim_norm
                wind_tot[j]+=sim_norm
            else
                f_sun[j] = sim_norm
                sun_tot[j]+=sim_norm
            end       
        end
        if (i<=40)
            forecasts[i]=f_wind
        else
            forecasts[i]=f_sun
        end      
    end 
    #forecasts
    #println(wind_tot)
    global sim_wind[k] = wind_tot
    #push!(sim_wind,wind_tot)
    #println(sim_wind)
    #append!(sim_wind,wind_tot)
    #sun_tot
    #ren_tot = sun_tot + wind_tot
    #=
    if k==10
    println(forecasts)
    println(wind_tot)
    end=#
end

mostrar_def=[]
for q in 1:24
    mostrar_element = [sim_wind[1,q] sim_wind[2,q] sim_wind[3,q] sim_wind[4,q]]
    append!(mostrar_def,mostrar_element)
end
mostrar_element
#println(sim_wind)
#horas = 1:24
#plot!(horas, [sim_wind], title="Predicciones eolicas")