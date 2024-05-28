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

#estas listas tendrán 24 listas. Estos vectores se graficarán
horas_eol = []
horas_sun = []
horas_sist = []
for _ in 1:2
    push!(horas_eol, 0)
    push!(horas_sun, 0)
    push!(horas_sist, 0)
end

#Cada uno de estos vectores incluye los 100 escenarios para una hora dada
esc_eol = []
esc_sun = []
esc_sist = []
for _ in 1:2
    push!(esc_eol, 0)
    push!(esc_sun, 0)
    push!(esc_sist, 0)
end

for e in 1:100    
    for t in 1:2
        tot_sun=0
        tot_eol=0
        for g in 1:60
            mu = renewables[g,1+t]                      #acá toma valor del excel
            if (g<=40)                                  #acá revisa si es solar o eólica
                m=(max_k_wind-min_k_wind)/(24-1)/100
                sigma = mu*(t*m+min_k_wind/100-m)
            else
                m=(max_k_sun-min_k_sun)/(24-1)/100
                sigma = mu*(t*m+min_k_sun/100-m)
            end
            sim_norm = mu + rand(Normal(0,sigma))       
            if (sim_norm<0)                             #trunca valores negativos
                sim_norm = 0
            end
            if (g<=40)
                tot_eol+=sim_norm
            else
                tot_sun+=sim_norm
            end  
        end
        esc_eol[t]=tot_eol
        esc_sun[t]=tot_sun
        esc_sist[t]=tot_eol+tot_sun
    end
    global horas_eol = hcat(horas_eol,esc_eol)
    global horas_sun=hcat(horas_sun,esc_sun)
    global horas_sist=hcat(horas_sist,esc_sist)
end
println(Float64.(horas_eol))

#horas = 1:24
#plot!(horas, Float64.(horas_eol), title="Predicciones eolicas")